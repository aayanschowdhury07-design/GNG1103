import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../csv.dart';
import '../l10n.dart';
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
      eyebrow: desk.me.role == 'clinician' ? tr('Your patients only') : null,
      title: tr('Reports'),
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
          child: Text(tr('Export CSV')),
        ),
      ],
      children: [
        KpiRow(children: [
          Kpi(label: tr('No-show rate'), value: pct(noShow, kept + noShow), sub: tr('{missed} missed of {due} visits due', {'missed': noShow, 'due': kept + noShow}), tone: noShow == 0 ? Tone.good : null),
          Kpi(label: tr('Cancellation rate'), value: pct(cancelled, all.length), sub: tr('{cancelled} of {total} bookings', {'cancelled': cancelled, 'total': all.length})),
          Kpi(label: tr('Average wait after check-in'), value: avgWait == null ? '—' : tr('{n} min', {'n': avgWait}), sub: waits.isEmpty ? tr('no visits called in yet') : trn(waits.length, 'over 1 visit', 'over {n} visits')),
          Kpi(label: tr('Freed times refilled, today'), value: freed.isEmpty ? '—' : pct(freed.where((f) => f.refilledBy != null).length, freed.length), sub: tr('{done} of {total}', {'done': freed.where((f) => f.refilledBy != null).length, 'total': freed.length})),
        ]),
        Columns(children: [
          Panel(
            title: tr('Volume by day, this week'),
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
                        Text(shortDate(day, lang: lang).split(' ').first + (day == today ? '\n${tr('today')}' : '\n'), textAlign: TextAlign.center, style: t.bodySmall),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
          Panel(
            title: tr('Utilization by clinician, this week'),
            child: Column(children: [
              for (final cl in clins)
                Builder(builder: (context) {
                  final cap = week.fold<int>(0, (n, day) => n + desk.capacity(cl, day)), n = week.fold<int>(0, (s, day) => s + desk.booked(cl, day));
                  return ShareBar(label: cl.short.isEmpty ? cl.name : cl.short, share: cap == 0 ? 0 : n / cap, figure: cap == 0 ? tr('not in') : '$n / $cap');
                }),
            ]),
          ),
        ]),
        Panel(
          title: tr('Volume by service'),
          child: Column(children: [
            for (final s in setup.services)
              ShareBar(label: s.name.split('·').first.trim(), share: (byService[s.id] ?? 0) / serviceTop, figure: '${byService[s.id] ?? 0}', flagLow: false),
            if (setup.services.isEmpty) Text(tr('No services yet.'), style: t.bodySmall),
          ]),
        ),
      ],
    );
  }
}
