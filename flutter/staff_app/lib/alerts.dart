import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'ui.dart';

/// What needs someone's attention right now, worked out live from the day: late patients,
/// freed times, unconfirmed visits and missing forms. Admins also see recent activity.
class AlertsTab extends StatelessWidget {
  const AlertsTab({super.key, required this.setup, required this.desk, required this.onWaitlist});
  final ClinicSetup setup;
  final ClinicDesk desk;
  final VoidCallback onWaitlist;

  /// How many things are listed under Needs attention (the number on the Alerts tab).
  static int count(ClinicDesk desk) {
    final mine = desk.todayVisits.where((a) => a.active && (desk.me.role != 'clinician' || a.clinicianId == desk.me.clinicianId)).toList();
    final late = mine.where(desk.isLate).length;
    final freed = desk.me.runsDay ? desk.freed.where((f) => f.date == desk.today && f.refilledBy == null).length : 0;
    final unconfirmed = mine.any((a) => a.status == ApptStatus.booked && !desk.isLate(a)) ? 1 : 0;
    final forms = mine.any((a) => !a.status.arrived && !a.formsDone) ? 1 : 0;
    return late + freed + unconfirmed + forms;
  }

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme, day = desk.today;
    final mine = desk.todayVisits.where((a) => a.active && (desk.me.role != 'clinician' || a.clinicianId == desk.me.clinicianId)).toList();
    final late = mine.where(desk.isLate).toList()..sort((a, b) => a.minute.compareTo(b.minute));
    final freed = desk.me.runsDay ? desk.freed.where((f) => f.date == day && f.refilledBy == null).toList() : const <FreedSlot>[];
    final unconfirmed = mine.where((a) => a.status == ApptStatus.booked && !desk.isLate(a)).toList();
    final formsOpen = mine.where((a) => !a.status.arrived && !a.formsDone).toList();

    Widget item({required IconData icon, required Color color, required String title, String? detail, List<Widget> actions = const []}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 36, height: 36, alignment: Alignment.center, decoration: BoxDecoration(color: color.withValues(alpha: .1), shape: BoxShape.circle), child: Icon(icon, size: 19, color: color)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.bodyLarge?.copyWith(color: c.fg, fontWeight: FontWeight.w600)),
                if (detail != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(detail, style: t.bodySmall)),
                if (actions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 8, runSpacing: 8, children: actions)),
              ]),
            ),
          ]),
        );

    final items = <Widget>[
      for (final a in late)
        item(
          icon: Icons.schedule,
          color: c.crit,
          title: tr('{name} is {n} min late', {'name': a.patientName, 'n': desk.lateBy(a)}),
          detail: tr('{time} with {clinician}, not checked in', {'time': formatTime(a.minute, lang: lang), 'clinician': clinicianShort(setup, a.clinicianId)}),
          actions: visitActions(context, desk, a),
        ),
      for (final f in freed)
        item(
          icon: Icons.event_available_outlined,
          color: c.warn,
          title: tr('{time} with {clinician} is free', {'time': formatTime(f.minute, lang: lang), 'clinician': clinicianShort(setup, f.clinicianId)}),
          detail: f.offeredTo != null ? tr('Offered to {name}', {'name': f.offeredTo!.name}) : tr('Cancelled. Open for booking.'),
          actions: [if (f.open && (setup.clinic['features'] as Map?)?['waitlist'] != false) small(tr('Offer from the waitlist'), onWaitlist)],
        ),
      if (unconfirmed.isNotEmpty)
        item(
          icon: Icons.help_outline,
          color: c.muted,
          title: trn(unconfirmed.length, '{n} visit today not confirmed', '{n} visits today not confirmed'),
          actions: [
            if (desk.me.runsDay)
              small(tr('Remind all'), () => act(context, () async {
                    for (final a in unconfirmed) {
                      await desk.remind(a);
                    }
                  }, done: trn(unconfirmed.length, '{n} reminder queued', '{n} reminders queued'))),
          ],
        ),
      if (formsOpen.isNotEmpty)
        item(
          icon: Icons.assignment_late_outlined,
          color: c.warn,
          title: trn(formsOpen.length, '{n} patient missing the reason-for-visit form', '{n} patients missing the reason-for-visit form'),
          actions: [
            if (desk.me.runsDay)
              small(tr('Resend'), () => act(context, () async {
                    for (final a in formsOpen) {
                      await desk.sendForm(a);
                    }
                  }, done: trn(formsOpen.length, '{n} form link queued', '{n} form links queued'))),
          ],
        ),
    ];

    final recent = desk.me.isAdmin ? desk.audit.take(8).toList() : const <AuditEntry>[];
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
      Text(tr('Alerts'), style: t.headlineMedium?.copyWith(fontSize: 30)),
      SectionHead(tr('Needs attention'), count: items.length),
      ...items,
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(children: [Icon(Icons.check_circle_outline, color: c.good), const SizedBox(width: 10), Text(tr('Nothing needs attention right now.'), style: t.bodyMedium)]),
        ),
      if (recent.isNotEmpty) ...[
        SectionHead(tr('Recent activity')),
        for (final e in recent)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.detail.isEmpty ? e.action : e.detail, style: t.bodyMedium?.copyWith(color: c.fg)),
                  Text(e.actor, style: t.bodySmall),
                ]),
              ),
              if (e.at != null) Text(TimeOfDay.fromDateTime(e.at!).format(context), style: t.bodySmall),
            ]),
          ),
      ],
    ]);
  }
}
