import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../csv.dart';
import '../ui.dart';
import '../visit.dart';

/// Figures worked out from the clinic's own records: attendance, waits, refills, volume and
/// how full each clinician's week is. Clinicians see their own; everyone else the clinic's.
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    final clins = visibleClinicians(setup, desk);
    final all = desk.appointments;
    // attendance: of the visits whose time has come, how many happened, were missed or cancelled
    final today = desk.today;
    final past = all.where((a) => desk.clock.passed(a.date, a.minute)).toList();
    final noShow = past.where((a) => a.status == ApptStatus.noShow && a.followUp != 'excused').length;
    final cancelled = all.where((a) => a.status == ApptStatus.cancelled).length;
    final kept = past.where((a) => a.status.arrived).length;
    final waits = [for (final a in all) if (a.calledAt != null && a.checkedInAt != null) a.calledAt! - a.checkedInAt!];
    final avgWait = waits.isEmpty ? null : (waits.reduce((a, b) => a + b) / waits.length).round();
    final freed = desk.freed;
    // this week, Monday to Saturday
    final d = DateTime.parse(today), monday = d.subtract(Duration(days: d.weekday - 1));
    final week = [for (var i = 0; i < 6; i++) isoDate(monday.add(Duration(days: i)))];
    final perDay = {for (final day in week) day: all.where((a) => a.date == day && a.active).length};
    final top = perDay.values.fold<int>(1, (m, n) => n > m ? n : m);
    final byService = <String, int>{};
    for (final a in all.where((a) => a.active)) {
      byService[a.serviceId] = (byService[a.serviceId] ?? 0) + 1;
    }
    final serviceTop = byService.values.fold<int>(1, (m, n) => n > m ? n : m);

    return PageFrame(
      eyebrow: 'From your clinic’s records${desk.me.role == 'clinician' ? ' · your patients' : ''}',
      title: 'Reports',
      actions: [
        OutlinedButton(
          style: smallButton,
          onPressed: () {
            downloadCsv('clinicflow-utilization.csv', [
              ['Clinician', 'Day', 'Booked', 'Bookable times'],
              for (final cl in clins)
                for (final day in week) [cl.name, day, desk.booked(cl, day), desk.capacity(cl, day)],
            ]);
            desk.record('export.csv', 'reports', '${clins.length * week.length} rows');
          },
          child: const Text('Export CSV'),
        ),
      ],
      children: [
        KpiRow(children: [
          Kpi(label: 'No-show rate', value: pct(noShow, kept + noShow), sub: '$noShow missed of ${kept + noShow} visits due', tone: noShow == 0 ? Tone.good : null),
          Kpi(label: 'Cancellation rate', value: pct(cancelled, all.length), sub: '$cancelled of ${all.length} bookings'),
          Kpi(label: 'Average wait after check-in', value: avgWait == null ? '—' : '$avgWait min', sub: waits.isEmpty ? 'no visits called in yet' : 'over ${waits.length} visits'),
          Kpi(label: 'Freed times refilled, today', value: freed.isEmpty ? '—' : pct(freed.where((f) => f.refilledBy != null).length, freed.length), sub: '${freed.where((f) => f.refilledBy != null).length} of ${freed.length}'),
        ]),
        Columns(children: [
          Panel(
            title: 'Volume by day, this week',
            note: 'Booked and completed visits. Today updates live.',
            child: SizedBox(
              height: 180,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final day in week)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text('${perDay[day]}', style: t.labelMedium),
                        const SizedBox(height: 4),
                        Container(
                          height: 120 * perDay[day]! / top,
                          decoration: BoxDecoration(color: day == today ? c.accent : c.accentSoft, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                        ),
                        const SizedBox(height: 6),
                        Text(shortDate(day).split(' ').first + (day == today ? '\ntoday' : '\n'), textAlign: TextAlign.center, style: t.bodySmall),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
          Panel(
            title: 'Utilization by clinician, this week',
            note: 'Booked share of each clinician’s bookable times, Monday to Saturday.',
            child: Column(children: [
              for (final cl in clins)
                Builder(builder: (context) {
                  final cap = week.fold<int>(0, (n, day) => n + desk.capacity(cl, day)), n = week.fold<int>(0, (s, day) => s + desk.booked(cl, day));
                  return ShareBar(label: cl.short.isEmpty ? cl.name : cl.short, share: cap == 0 ? 0 : n / cap, figure: cap == 0 ? 'not in' : '$n / $cap');
                }),
            ]),
          ),
        ]),
        Panel(
          title: 'Volume by service',
          note: 'All recorded bookings that weren’t cancelled or missed.',
          child: Column(children: [
            for (final s in setup.services)
              ShareBar(label: s.name.split('·').first.trim(), share: (byService[s.id] ?? 0) / serviceTop, figure: '${byService[s.id] ?? 0}', flagLow: false),
            if (setup.services.isEmpty) Text('No services yet.', style: t.bodySmall),
          ]),
        ),
      ],
    );
  }
}
