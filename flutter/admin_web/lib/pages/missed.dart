import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../csv.dart';
import '../l10n.dart';
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
          'contacted' => tr('Rebooking link to {name} queued', {'name': first}),
          'excused' => tr('Excused. Not counted in the no-show rate.'),
          _ => tr('Marked rebooked'),
        },
        undo: to == 'contacted' ? null : () => desk.followUp(a, before),
      );
    }

    return PageFrame(
      eyebrow: tr('Last 30 days'),
      title: tr('Missed visits'),
      actions: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [ButtonSegment(value: false, label: Text(tr('Needs follow-up'))), ButtonSegment(value: true, label: Text(tr('All')))],
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
          child: Text(tr('Export CSV')),
        ),
      ],
      children: [
        KpiRow(children: [
          Kpi(label: tr('Missed, 30 days'), value: '${missed.length}', sub: tr('{n} excused', {'n': missed.where((a) => state(a) == 'excused').length})),
          Kpi(label: tr('Need follow-up'), value: '$open', sub: open > 0 ? tr('send a rebooking link') : tr('all handled'), tone: open > 0 ? Tone.warn : Tone.good),
          Kpi(label: tr('Rebooked'), value: '${missed.where((a) => state(a) == 'rebooked').length}', sub: tr('of {n} missed', {'n': missed.length})),
          Kpi(label: tr('Repeat no-shows'), value: '${missed.where((a) => times(a) > 1).map((a) => a.patientName).toSet().length}', sub: tr('missed more than once')),
        ]),
        Panel(
          child: SimpleTable(
            columns: [tr('Missed'), tr('Patient'), tr('Clinician'), tr('Status'), ''],
            empty: _all ? tr('No missed visits in the last 30 days.') : tr('Nothing to follow up. Switch to All to see handled visits.'),
            rows: [
              for (final a in rows)
                [
                  Text('${shortDate(a.date, lang: lang)} · ${formatTime(a.minute, lang: lang)}', style: t.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(a.patientName),
                      if (times(a) > 1) ...[const SizedBox(width: 6), Pill(tr('{n}× missed', {'n': times(a)}), tone: Tone.crit)],
                    ]),
                    Text(serviceName(setup, a.serviceId), style: t.bodySmall),
                  ]),
                  Text(clinicianShort(setup, a.clinicianId), style: t.bodySmall),
                  Pill(tr(_follow[state(a)]!.$1), tone: _follow[state(a)]!.$2),
                  RowActions(switch (state(a)) {
                    'open' => [small(tr('Send rebooking link'), () => follow(a, 'contacted'), primary: true), small(tr('Excuse'), () => follow(a, 'excused'))],
                    'contacted' => [small(tr('Mark rebooked'), () => follow(a, 'rebooked'))],
                    _ => const <Widget>[],
                  }),
                ],
            ],
          ),
        ),
        Text(tr('“Excused” keeps a missed visit out of the no-show rate.'), style: t.bodySmall),
      ],
    );
  }
}
