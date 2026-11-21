import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
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
      eyebrow: tr('Live · {time}', {'time': formatTime(desk.nowMinute, lang: lang)}),
      title: tr('Waiting room'),
      actions: [
        OutlinedButton(
          style: smallButton,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => TvBoard(setup: setup, desk: desk))),
          child: Text(tr('Open TV board')),
        ),
      ],
      children: [
        Panel(
          child: desk.me.readOnly
              ? _TicketsOnly(desk: desk)
              : SimpleTable(
                  columns: [tr('Ticket'), tr('Patient'), tr('Appt'), tr('Status'), tr('Waited'), tr('Form'), ''],
                  empty: tr('Nobody has arrived yet.'),
                  rows: [
                    for (final a in here)
                      [
                        Text(a.ticket ?? '—', style: t.labelLarge),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.patientName), Text(clinicianShort(setup, a.clinicianId), style: t.bodySmall)]),
                        Text(formatTime(a.minute, lang: lang)),
                        StatusMark(shownStatus(desk, a), label: tr(shownStatus(desk, a).label)),
                        Text(a.status == ApptStatus.waiting || a.status == ApptStatus.checkedIn
                            ? tr('{n} min', {'n': desk.waited(a)})
                            : desk.isLate(a)
                                ? tr('{n} min late', {'n': desk.lateBy(a)})
                                : ''),
                        a.formsDone ? Pill(tr('Done'), tone: Tone.good) : Pill(tr('Open'), tone: Tone.warn),
                        RowActions(visitActions(context, desk, a, primary: a == next)),
                      ],
                  ],
                ),
        ),
        Columns(children: [
          _Board(desk: desk, compact: true),
          Panel(
            title: tr('Self check-in'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_checkInText(setup), style: t.bodySmall),
              const SizedBox(height: 10),
              if (desk.me.runsDay && _on(setup, 'kiosk')) OutlinedButton(style: smallButton, onPressed: () => onGo(StaffPage.kiosk), child: Text(tr('Open check-in tablet'))),
            ]),
          ),
        ]),
        if (!desk.me.readOnly)
          Panel(
            title: tr('Expected in the next 2 hours'),
            child: SimpleTable(
              columns: [tr('Appt'), tr('Patient'), tr('Status'), tr('Form'), ''],
              empty: tr('No one else is due in the next 2 hours.'),
              rows: [
                for (final a in expected)
                  [
                    Text(formatTime(a.minute, lang: lang)),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.patientName), Text(clinicianShort(setup, a.clinicianId), style: t.bodySmall)]),
                    StatusMark(a.status, label: tr(a.status.label)),
                    a.formsDone ? Pill(tr('Done'), tone: Tone.good) : Pill(tr('Open'), tone: Tone.warn),
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
      columns: [tr('Ticket'), tr('Status')],
      empty: tr('Nobody is in the waiting room.'),
      rows: [
        for (final x in q) [Text('${x['ticket']}'), _mark(ApptStatus.values.asNameMap()['${x['status']}'] ?? ApptStatus.checkedIn)],
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
        Text(tr('Now serving'), style: t.labelLarge?.copyWith(color: c.heroFg.withValues(alpha: .75), fontSize: compact ? 14 : 28)),
        Text(serving.isEmpty ? '—' : serving.join(', '), style: TextStyle(color: c.heroFg, fontSize: big, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 8),
        Text(up.isEmpty ? tr('No one waiting') : tr('Next: {tickets}', {'tickets': up.join('   ')}), style: TextStyle(color: c.heroFg, fontSize: compact ? 18 : 44, fontWeight: FontWeight.w500)),
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

bool _on(ClinicSetup setup, String feature) => (setup.clinic['features'] as Map?)?[feature] != false;

/// How patients check in at this clinic, from the features it uses (Settings).
String _checkInText(ClinicSetup setup) {
  final phone = _on(setup, 'phoneCheckIn'), tablet = _on(setup, 'kiosk');
  final near = _on(setup, 'locationCheck') ? tr(', within 200 m of the clinic') : '';
  if (phone && tablet) return tr('Patients check in on their phone from 60 minutes before{near}, or on the front-desk tablet with the last 4 digits of their phone number.', {'near': near});
  if (phone) return tr('Patients check in on their phone from 60 minutes before{near}. The check-in tablet is off (Settings).', {'near': near});
  if (tablet) return tr('Patients check in on the front-desk tablet with the last 4 digits of their phone number. Phone check-in is off (Settings).');
  return tr('Self check-in is off (Settings): the front desk checks patients in from the calendar or this page.');
}

Widget _mark(ApptStatus s) => StatusMark(s, label: tr(s.label));
