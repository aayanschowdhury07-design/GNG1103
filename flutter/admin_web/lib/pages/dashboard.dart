import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n.dart';
import '../shell.dart';
import '../ui.dart';
import '../visit.dart';

String bookingUrl(ClinicSetup s) => bookingLink(s.clinicId ?? '');

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
          Pill(tr('Late'), tone: Tone.crit),
          Text(tr('{patient} · {time} with {clinician}', {'patient': a.patientName, 'time': formatTime(a.minute, lang: lang), 'clinician': clinicianShort(setup, a.clinicianId)})),
          Text(tr('{n} min late, not checked in', {'n': desk.lateBy(a)}), style: t.bodySmall),
          RowActions(visitActions(context, desk, a)),
        ],
      for (final f in freed)
        [
          Pill(tr('Freed'), tone: Tone.warn),
          Text(tr('{time} with {clinician} is free', {'time': formatTime(f.minute, lang: lang), 'clinician': clinicianShort(setup, f.clinicianId)})),
          Text(f.offeredTo != null ? tr('offered to {name}', {'name': f.offeredTo!.name}) : tr('open for booking'), style: t.bodySmall),
          RowActions([if ((setup.clinic['features'] as Map?)?['waitlist'] != false) small(tr('View'), () => onGo(StaffPage.wait))]),
        ],
      if (unconfirmed.isNotEmpty)
        [
          Pill(tr('Unconfirmed')),
          Text(trn(unconfirmed.length, '{n} visit today not confirmed', '{n} visits today not confirmed')),
          const SizedBox(),
          RowActions([
            if (desk.me.runsDay)
              small(tr('Remind all'), () => act(context, () async {
                    for (final a in unconfirmed) {
                      await desk.remind(a);
                    }
                  }, done: trn(unconfirmed.length, '{n} reminder queued', '{n} reminders queued'))),
          ]),
        ],
      if (formsOpen.isNotEmpty)
        [
          Pill(tr('Forms'), tone: Tone.warn),
          Text(trn(formsOpen.length, '{n} patient missing the reason-for-visit form', '{n} patients missing the reason-for-visit form')),
          const SizedBox(),
          RowActions([
            if (desk.me.runsDay)
              small(tr('Resend'), () => act(context, () async {
                    for (final a in formsOpen) {
                      await desk.sendForm(a);
                    }
                  }, done: trn(formsOpen.length, '{n} form link queued', '{n} form links queued'))),
          ]),
        ],
      if (desk.me.isAdmin && missingFr > 0)
        [
          Pill(tr('Setup'), tone: Tone.info),
          Text(tr('French message wording')),
          Text(tr('{n} of {total} templates not translated', {'n': missingFr, 'total': messageTemplates.length}), style: t.bodySmall),
          RowActions([small(tr('Fix'), () => onGo(StaffPage.notif))]),
        ],
    ];

    final first = (desk.me.name.isEmpty ? '' : desk.me.name).replaceFirst(RegExp(r'^Dr\.?\s+'), '').split(' ').first;
    final hour = desk.nowMinute ~/ 60;
    final hello = hour < 12 ? tr('Good morning') : hour < 18 ? tr('Good afternoon') : tr('Good evening');
    final upcoming = today.where((a) => a.status.upcoming && !desk.isLate(a)).take(6).toList();
    final waitlistOn = (setup.clinic['features'] as Map?)?['waitlist'] != false;

    return PageFrame(
      title: first.isEmpty ? hello : '$hello, $first',
      eyebrow: tr('Here’s what’s happening at {clinic} today.', {'clinic': setup.clinic['name'] ?? ''}),
      children: [
        Columns(flex: const [13, 5], stackBelow: 1060, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KpiRow(children: [
              Kpi(icon: Icons.calendar_today_outlined, label: tr('Booked today'), value: '${today.length}', sub: tr('of {cap} times · {pct}', {'cap': cap, 'pct': pct(today.length, cap)})),
              Kpi(icon: Icons.schedule, label: tr('In the waiting room'), value: '${waiting.length}', sub: waiting.isEmpty ? tr('nobody waiting') : tr('average wait {n} min', {'n': avgWait})),
              Kpi(icon: Icons.event_busy_outlined, label: tr('No-show rate, 30 days'), value: pct(missed, seen), sub: seen == 0 ? tr('no finished visits yet') : tr('{missed} of {seen} visits', {'missed': missed, 'seen': seen}), tone: missed == 0 ? Tone.good : null),
              Kpi(
                icon: Icons.assignment_turned_in_outlined,
                label: tr('Intake complete'),
                value: '${stillToCome.length - formsOpen.length} / ${stillToCome.length}',
                sub: formsOpen.isEmpty ? tr('all forms in') : trn(formsOpen.length, '{n} form open', '{n} forms open'),
                tone: formsOpen.isEmpty ? Tone.good : Tone.warn,
              ),
              if (desk.me.runsDay) Kpi(icon: Icons.playlist_add_check, label: tr('On the waitlist'), value: '${desk.waitlist.length}', sub: tr('{n} flagged priority', {'n': desk.waitlist.where((w) => w.priority).length})),
            ]),
            const SizedBox(height: 36),
            Panel(
              title: tr('Needs attention'),
              trailing: Pill('${attention.length}', tone: attention.isEmpty ? Tone.good : Tone.warn),
              child: SimpleTable(columns: ['', tr('What'), tr('Detail'), ''], rows: attention, empty: tr('Nothing needs attention right now.')),
            ),
            const SizedBox(height: 36),
            Panel(
              title: tr('Still to come today'),
              trailing: TextButton.icon(onPressed: () => onGo(StaffPage.cal), iconAlignment: IconAlignment.end, icon: const Icon(Icons.arrow_forward, size: 16), label: Text(tr('Calendar'))),
              child: SimpleTable(
                columns: [tr('Time'), tr('Patient'), tr('Clinician'), tr('Status')],
                rows: [
                  for (final a in upcoming)
                    [
                      Text(formatTime(a.minute, lang: lang), style: t.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                      Text(a.patientName),
                      Text(clinicianShort(setup, a.clinicianId)),
                      StatusMark(a.status, label: tr(a.status.label)),
                    ],
                ],
                empty: tr('No more visits today.'),
              ),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Panel(
              title: tr('Quick actions'),
              child: Column(children: [
                if (desk.me.runsDay) ...[
                  _QuickAction(Icons.calendar_today_outlined, tr('Book a patient'), () => onGo(StaffPage.cal, book: true)),
                  _QuickAction(Icons.link, tr('Copy booking link'), () {
                    Clipboard.setData(ClipboardData(text: bookingUrl(setup)));
                    say(context, tr('Copied {link}', {'link': bookingUrl(setup).replaceFirst('https://', '')}));
                  }),
                  _QuickAction(Icons.qr_code_2, tr('Booking QR code'), () => _showQr(context, setup)),
                ],
                _QuickAction(Icons.groups_outlined, tr('Live queue'), () => onGo(StaffPage.queue)),
                if (desk.me.runsDay && waitlistOn) _QuickAction(Icons.playlist_add_check, tr('Waitlist & recovery'), () => onGo(StaffPage.wait)),
                if (desk.me.isAdmin) _QuickAction(Icons.manage_accounts_outlined, tr('Users & roles'), () => onGo(StaffPage.users), last: true),
              ]),
            ),
            const SizedBox(height: 36),
            Panel(
              title: tr('Utilization by clinician, today'),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(children: [
                  for (final c in clins)
                    if (desk.capacity(c, day) > 0)
                      ShareBar(label: c.short.isEmpty ? c.name : c.short, share: desk.booked(c, day) / desk.capacity(c, day), figure: pct(desk.booked(c, day), desk.capacity(c, day))),
                  if (clins.every((c) => desk.capacity(c, day) == 0)) Align(alignment: Alignment.centerLeft, child: Text(tr('Nobody is in today.'), style: t.bodySmall)),
                ]),
              ),
            ),
          ]),
        ]),
      ],
    );
  }
}

/// One line in Quick actions: icon, label, chevron; a thin rule under all but the last.
class _QuickAction extends StatelessWidget {
  const _QuickAction(this.icon, this.label, this.onTap, {this.last = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.line))),
        child: Row(children: [
          Icon(icon, size: 21, color: c.accent),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: t.bodyMedium?.copyWith(color: c.fg))),
          Icon(Icons.chevron_right, size: 18, color: c.muted),
        ]),
      ),
    );
  }
}

void _showQr(BuildContext context, ClinicSetup setup) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Booking QR code')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(color: Colors.white, padding: const EdgeInsets.all(12), child: QrImageView(data: bookingUrl(setup), size: 220, semanticsLabel: tr('QR code for {link}', {'link': bookingUrl(setup)}))),
          const SizedBox(height: 12),
          SelectableText(bookingUrl(setup)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close')))],
      ),
    );
