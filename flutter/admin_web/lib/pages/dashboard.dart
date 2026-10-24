import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../shell.dart';
import '../ui.dart';
import '../visit.dart';

String bookingUrl(ClinicSetup s) => 'https://book.clinicflow.ca/${s.clinicId}';

/// Today at a glance: how full the day is, who's waiting, and what needs someone's attention.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.setup, required this.desk, required this.onGo});
  final ClinicSetup setup;
  final ClinicDesk desk;
  final void Function(StaffPage, {bool book}) onGo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final clins = visibleClinicians(setup, desk);
    final day = desk.today;
    final today = desk.todayVisits.where((a) => a.active).toList();
    final cap = clins.fold<int>(0, (n, c) => n + desk.capacity(c, day));
    final waiting = today.where((a) => a.status == ApptStatus.waiting || a.status == ApptStatus.checkedIn).toList();
    final avgWait = waiting.isEmpty ? 0 : (waiting.fold<int>(0, (n, a) => n + desk.waited(a)) / waiting.length).round();
    final stillToCome = today.where((a) => !a.status.arrived).toList();
    final formsOpen = stillToCome.where((a) => !a.formsDone).toList();
    final unconfirmed = today.where((a) => a.status == ApptStatus.booked && !desk.isLate(a)).toList();
    // no-show rate over the 30 days up to today, from what was recorded
    final from = addDays(day, -30);
    final recent = desk.appointments.where((a) => a.date.compareTo(from) >= 0 && a.date.compareTo(day) <= 0);
    final missed = recent.where((a) => a.status == ApptStatus.noShow && a.followUp != 'excused').length;
    final seen = recent.where((a) => a.status == ApptStatus.complete).length + missed;
    final late = today.where(desk.isLate).toList();
    // today's freed times; later ones are on the waitlist page
    final freed = desk.me.runsDay ? desk.freed.where((f) => f.date == day && f.refilledBy == null).toList() : const <FreedSlot>[];
    final missingFr = messageTemplates.keys.where((k) => desk.template(k, 'fr').isEmpty).length;

    final attention = <List<Widget>>[
      for (final a in late)
        [
          const Pill('Late', tone: Tone.crit),
          Text('${a.patientName} · ${formatTime(a.minute)} with ${clinicianShort(setup, a.clinicianId)}'),
          Text('${desk.lateBy(a)} min late, not checked in', style: t.bodySmall),
          RowActions(visitActions(context, desk, a)),
        ],
      for (final f in freed)
        [
          const Pill('Freed', tone: Tone.warn),
          Text('${formatTime(f.minute)} with ${clinicianShort(setup, f.clinicianId)} is free'),
          Text(f.offeredTo != null ? 'offered to ${f.offeredTo!.name}' : 'open for booking', style: t.bodySmall),
          RowActions([small('View', () => onGo(StaffPage.wait))]),
        ],
      if (unconfirmed.isNotEmpty)
        [
          const Pill('Unconfirmed'),
          Text('${unconfirmed.length} visit${unconfirmed.length == 1 ? '' : 's'} today not confirmed'),
          Text('reminders have a one-tap confirm', style: t.bodySmall),
          RowActions([
            if (desk.me.runsDay)
              small('Remind all', () => act(context, () async {
                    for (final a in unconfirmed) {
                      await desk.remind(a);
                    }
                  }, done: '${unconfirmed.length} reminders queued')),
          ]),
        ],
      if (formsOpen.isNotEmpty)
        [
          const Pill('Forms', tone: Tone.warn),
          Text('${formsOpen.length} patient${formsOpen.length == 1 ? '' : 's'} missing the reason-for-visit form'),
          Text('the form link is in their booking message', style: t.bodySmall),
          RowActions([
            if (desk.me.runsDay)
              small('Resend', () => act(context, () async {
                    for (final a in formsOpen) {
                      await desk.sendForm(a);
                    }
                  }, done: '${formsOpen.length} form links queued')),
          ]),
        ],
      if (desk.me.isAdmin && missingFr > 0)
        [
          const Pill('Setup', tone: Tone.info),
          const Text('French message wording'),
          Text('$missingFr of ${messageTemplates.length} templates not translated', style: t.bodySmall),
          RowActions([small('Fix', () => onGo(StaffPage.notif))]),
        ],
    ];

    return PageFrame(
      eyebrow: longDay(day, day),
      title: 'Dashboard',
      actions: [
        if (desk.me.runsDay) ...[
          OutlinedButton(
            style: smallButton,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: bookingUrl(setup)));
              say(context, 'Copied ${bookingUrl(setup).replaceFirst('https://', '')}');
            },
            child: const Text('Copy booking link'),
          ),
          OutlinedButton(style: smallButton, onPressed: () => _showQr(context, setup), child: const Text('Booking QR code')),
          FilledButton(style: smallFilled, onPressed: () => onGo(StaffPage.cal, book: true), child: const Text('Book a patient')),
        ],
      ],
      children: [
        KpiRow(children: [
          Kpi(label: 'Booked today', value: '${today.length}', sub: 'of $cap times · ${pct(today.length, cap)}'),
          Kpi(label: 'In the waiting room', value: '${waiting.length}', sub: waiting.isEmpty ? 'nobody waiting' : 'average wait $avgWait min'),
          Kpi(label: 'No-show rate, 30 days', value: pct(missed, seen), sub: seen == 0 ? 'no finished visits yet' : '$missed of $seen visits', tone: missed == 0 ? Tone.good : null),
          Kpi(label: 'Intake complete', value: '${stillToCome.length - formsOpen.length} / ${stillToCome.length}', sub: formsOpen.isEmpty ? 'all forms in' : '${formsOpen.length} forms open', tone: formsOpen.isEmpty ? Tone.good : Tone.warn),
          if (desk.me.runsDay) Kpi(label: 'On the waitlist', value: '${desk.waitlist.length}', sub: '${desk.waitlist.where((w) => w.priority).length} flagged priority'),
        ]),
        Panel(
          title: 'Needs attention',
          trailing: Pill('${attention.length}', tone: attention.isEmpty ? Tone.good : Tone.warn),
          child: SimpleTable(columns: const ['', 'What', 'Detail', ''], rows: attention, empty: 'Nothing needs attention right now.'),
        ),
        Columns(children: [
          Panel(
            title: 'Utilization by clinician, today',
            note: 'Share of each clinician’s bookable time that is booked.',
            child: Column(children: [
              for (final c in clins)
                if (desk.capacity(c, day) > 0)
                  ShareBar(label: c.short.isEmpty ? c.name : c.short, share: desk.booked(c, day) / desk.capacity(c, day), figure: pct(desk.booked(c, day), desk.capacity(c, day))),
              if (clins.every((c) => desk.capacity(c, day) == 0)) Text('Nobody is in today.', style: t.bodySmall),
            ]),
          ),
          Panel(
            title: 'Still to come today',
            note: 'Visits after now, by time.',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final a in today.where((a) => a.status.upcoming && !desk.isLate(a)).take(6))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 72, child: Text(formatTime(a.minute), style: t.bodySmall)),
                    Expanded(child: Text('${a.patientName} · ${clinicianShort(setup, a.clinicianId)}', overflow: TextOverflow.ellipsis)),
                    StatusMark(a.status),
                  ]),
                ),
              if (!today.any((a) => a.status.upcoming && !desk.isLate(a))) Text('No more visits today.', style: t.bodySmall),
            ]),
          ),
        ]),
      ],
    );
  }
}

void _showQr(BuildContext context, ClinicSetup setup) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Booking QR code'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(color: Colors.white, padding: const EdgeInsets.all(12), child: QrImageView(data: bookingUrl(setup), size: 220, semanticsLabel: 'QR code for ${bookingUrl(setup)}')),
          const SizedBox(height: 12),
          SelectableText(bookingUrl(setup)),
          const SizedBox(height: 4),
          Text('Print it for the front desk, the door and appointment cards.', style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
