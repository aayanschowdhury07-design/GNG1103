import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../csv.dart';
import '../ui.dart';
import '../visit.dart';

const _follow = {
  'open': ('Needs follow-up', Tone.crit),
  'contacted': ('Contacted', Tone.warn),
  'rebooked': ('Rebooked', Tone.good),
  'excused': ('Excused', Tone.mute),
};

/// No-shows, and following each one up: a rebooking link, rebooked, or excused.
class MissedPage extends StatefulWidget {
  const MissedPage({super.key, required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;
  @override
  State<MissedPage> createState() => _MissedPageState();
}

class _MissedPageState extends State<MissedPage> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, desk = widget.desk, setup = widget.setup;
    final from = addDays(desk.today, -30);
    final missed = desk.missed.where((a) => a.date.compareTo(from) >= 0).toList();
    String state(DeskAppt a) => a.followUp ?? 'open';
    // the same person (same name and phone) missing more than once
    int times(DeskAppt a) => desk.missed.where((x) => x.patientName == a.patientName && x.phoneLast4 == a.phoneLast4).length;
    final open = missed.where((a) => state(a) == 'open').length;
    final rows = missed.where((a) => _all || state(a) == 'open' || state(a) == 'contacted').toList();

    Future<void> follow(DeskAppt a, String to) {
      final first = a.patientName.split(' ').first, before = state(a);
      return act(
        context,
        () => desk.followUp(a, to),
        done: switch (to) {
          'contacted' => 'Rebooking link to $first queued',
          'excused' => 'Excused. Not counted in the no-show rate.',
          _ => 'Marked rebooked',
        },
        undo: to == 'contacted' ? null : () => desk.followUp(a, before),
      );
    }

    return PageFrame(
      eyebrow: 'Last 30 days',
      title: 'Missed visits',
      actions: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: false, label: Text('Needs follow-up')), ButtonSegment(value: true, label: Text('All'))],
          selected: {_all},
          onSelectionChanged: (v) => setState(() => _all = v.first),
        ),
        OutlinedButton(
          style: smallButton,
          onPressed: () {
            downloadCsv('clinicflow-missed.csv', [
              ['Date', 'Time', 'Patient', 'Clinician', 'Service', 'Status'],
              for (final a in missed) [a.date, formatTime(a.minute), a.patientName, clinicianShort(setup, a.clinicianId), serviceName(setup, a.serviceId), _follow[state(a)]!.$1],
            ]);
            desk.record('export.csv', 'missed', '${missed.length} rows');
          },
          child: const Text('Export CSV'),
        ),
      ],
      children: [
        KpiRow(children: [
          Kpi(label: 'Missed, 30 days', value: '${missed.length}', sub: '${missed.where((a) => state(a) == 'excused').length} excused'),
          Kpi(label: 'Need follow-up', value: '$open', sub: open > 0 ? 'send a rebooking link' : 'all handled', tone: open > 0 ? Tone.warn : Tone.good),
          Kpi(label: 'Rebooked', value: '${missed.where((a) => state(a) == 'rebooked').length}', sub: 'of ${missed.length} missed'),
          Kpi(label: 'Repeat no-shows', value: '${missed.where((a) => times(a) > 1).map((a) => a.patientName).toSet().length}', sub: 'missed more than once'),
        ]),
        Panel(
          child: SimpleTable(
            columns: const ['Missed', 'Patient', 'Clinician', 'Status', ''],
            empty: _all ? 'No missed visits in the last 30 days.' : 'Nothing to follow up. Switch to All to see handled visits.',
            rows: [
              for (final a in rows)
                [
                  Text('${shortDate(a.date)} · ${formatTime(a.minute)}', style: t.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(a.patientName),
                      if (times(a) > 1) ...[const SizedBox(width: 6), Pill('${times(a)}× missed', tone: Tone.crit)],
                    ]),
                    Text(serviceName(setup, a.serviceId), style: t.bodySmall),
                  ]),
                  Text(clinicianShort(setup, a.clinicianId), style: t.bodySmall),
                  Pill(_follow[state(a)]!.$1, tone: _follow[state(a)]!.$2),
                  RowActions(switch (state(a)) {
                    'open' => [small('Send rebooking link', () => follow(a, 'contacted'), primary: true), small('Excuse', () => follow(a, 'excused'))],
                    'contacted' => [small('Mark rebooked', () => follow(a, 'rebooked'))],
                    _ => const <Widget>[],
                  }),
                ],
            ],
          ),
        ),
        Text('No-shows marked in the queue or the staff app land here right away. “Excused” keeps them out of the no-show rate, for example when a patient was in hospital.', style: t.bodySmall),
      ],
    );
  }
}
