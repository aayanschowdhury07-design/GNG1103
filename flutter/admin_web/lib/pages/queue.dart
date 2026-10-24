import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../shell.dart';
import '../ui.dart';
import '../visit.dart';

int _ticketNo(String? t) => int.tryParse((t ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0;

/// The waiting room, live: who has arrived, how long they've waited, and the next step for each.
/// The same actions as the staff app, so the front desk can run the queue from either.
class QueuePage extends StatelessWidget {
  const QueuePage({super.key, required this.setup, required this.desk, required this.onGo});
  final ClinicSetup setup;
  final ClinicDesk desk;
  final void Function(StaffPage, {bool book}) onGo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const order = {ApptStatus.inVisit: 0, ApptStatus.waiting: 1, ApptStatus.checkedIn: 2, ApptStatus.late: 3, ApptStatus.complete: 4};
    final today = desk.todayVisits.where((a) => a.active).toList();
    final here = today.where((a) => a.status.arrived || desk.isLate(a)).toList()
      ..sort((a, b) => (order[shownStatus(desk, a)] ?? 9) - (order[shownStatus(desk, b)] ?? 9) != 0
          ? (order[shownStatus(desk, a)] ?? 9) - (order[shownStatus(desk, b)] ?? 9)
          : _ticketNo(a.ticket) - _ticketNo(b.ticket) != 0
              ? _ticketNo(a.ticket) - _ticketNo(b.ticket)
              : a.minute - b.minute);
    final next = here.where((a) => a.status == ApptStatus.waiting && canActOn(desk, a)).firstOrNull;
    final expected = today.where((a) => a.status.upcoming && !desk.isLate(a) && a.minute <= desk.nowMinute + 120).toList();

    return PageFrame(
      eyebrow: 'Live · ${formatTime(desk.nowMinute)}',
      title: 'Waiting room',
      actions: [
        OutlinedButton(
          style: smallButton,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => TvBoard(setup: setup, desk: desk))),
          child: const Text('Open TV board'),
        ),
      ],
      children: [
        Panel(
          child: desk.me.readOnly
              ? _TicketsOnly(desk: desk)
              : SimpleTable(
                  columns: const ['Ticket', 'Patient', 'Appt', 'Status', 'Waited', 'Form', ''],
                  empty: 'Nobody has arrived yet.',
                  rows: [
                    for (final a in here)
                      [
                        Text(a.ticket ?? '—', style: t.labelLarge),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.patientName), Text(clinicianShort(setup, a.clinicianId), style: t.bodySmall)]),
                        Text(formatTime(a.minute)),
                        StatusMark(shownStatus(desk, a)),
                        Text(a.status == ApptStatus.waiting || a.status == ApptStatus.checkedIn
                            ? '${desk.waited(a)} min'
                            : desk.isLate(a)
                                ? '${desk.lateBy(a)} min late'
                                : ''),
                        a.formsDone ? const Pill('Done', tone: Tone.good) : const Pill('Open', tone: Tone.warn),
                        RowActions(visitActions(context, desk, a, primary: a == next)),
                      ],
                  ],
                ),
        ),
        Columns(children: [
          _Board(desk: desk, compact: true),
          Panel(
            title: 'Self check-in',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Patients check in on their phone from 60 minutes before, within 200 m of the clinic, or on the front-desk tablet with the last 4 digits of their phone number.', style: t.bodySmall),
              const SizedBox(height: 10),
              if (desk.me.runsDay) OutlinedButton(style: smallButton, onPressed: () => onGo(StaffPage.kiosk), child: const Text('Open check-in tablet')),
            ]),
          ),
        ]),
        if (!desk.me.readOnly)
          Panel(
            title: 'Expected in the next 2 hours',
            child: SimpleTable(
              columns: const ['Appt', 'Patient', 'Status', 'Form', ''],
              empty: 'No one else is due in the next 2 hours.',
              rows: [
                for (final a in expected)
                  [
                    Text(formatTime(a.minute)),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.patientName), Text(clinicianShort(setup, a.clinicianId), style: t.bodySmall)]),
                    StatusMark(a.status),
                    a.formsDone ? const Pill('Done', tone: Tone.good) : const Pill('Open', tone: Tone.warn),
                    RowActions(visitActions(context, desk, a)),
                  ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Support staff see ticket numbers and statuses only, like the waiting-room board.
class _TicketsOnly extends StatelessWidget {
  const _TicketsOnly({required this.desk});
  final ClinicDesk desk;
  @override
  Widget build(BuildContext context) {
    final q = [...desk.queue.where((x) => x['status'] != 'complete')]..sort((a, b) => ((a['n'] as int?) ?? 0) - ((b['n'] as int?) ?? 0));
    return SimpleTable(
      columns: const ['Ticket', 'Status'],
      empty: 'Nobody is in the waiting room.',
      rows: [
        for (final x in q) [Text('${x['ticket']}'), StatusMark(ApptStatus.values.asNameMap()['${x['status']}'] ?? ApptStatus.checkedIn)],
      ],
    );
  }
}

/// Now serving and the next three tickets. Ticket numbers only: no names on a public screen.
class _Board extends StatelessWidget {
  const _Board({required this.desk, this.compact = false});
  final ClinicDesk desk;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final serving = desk.queue.where((x) => x['status'] == ApptStatus.inVisit.name).map((x) => '${x['ticket']}').toList()..sort();
    final waiting = [...desk.queue.where((x) => x['status'] == ApptStatus.waiting.name)]..sort((a, b) => ((a['n'] as int?) ?? 0) - ((b['n'] as int?) ?? 0));
    final up = waiting.take(3).map((x) => '${x['ticket']}').toList();
    final big = compact ? 40.0 : 120.0;
    return Container(
      padding: EdgeInsets.all(compact ? 20 : 48),
      decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(compact ? 12 : 0)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Now serving', style: t.labelLarge?.copyWith(color: c.heroFg.withValues(alpha: .75), fontSize: compact ? 14 : 28)),
        Text(serving.isEmpty ? '—' : serving.join(', '), style: TextStyle(color: c.heroFg, fontSize: big, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 8),
        Text(up.isEmpty ? 'No one waiting' : 'Next: ${up.join('   ')}', style: TextStyle(color: c.heroFg, fontSize: compact ? 18 : 44, fontWeight: FontWeight.w500)),
        SizedBox(height: compact ? 12 : 32),
        Text('Ticket numbers only. No names on the board.', style: t.bodySmall?.copyWith(color: c.heroFg.withValues(alpha: .7), fontSize: compact ? 12 : 20)),
      ]),
    );
  }
}

/// The waiting-room TV: full screen, updating live.
class TvBoard extends StatelessWidget {
  const TvBoard({super.key, required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context);
    return Scaffold(
      backgroundColor: c.hero,
      appBar: AppBar(backgroundColor: c.hero, foregroundColor: c.heroFg, title: Text(setup.clinic['name'] ?? '', style: TextStyle(color: c.heroFg))),
      body: ListenableBuilder(listenable: desk, builder: (context, _) => SizedBox.expand(child: _Board(desk: desk))),
    );
  }
}
