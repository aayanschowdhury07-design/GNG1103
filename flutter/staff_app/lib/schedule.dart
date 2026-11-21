import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'portal_theme.dart';
import 'ui.dart';

/// A clinician's day, time by time: who's booked, what's open, and breaks or time off.
class ScheduleTab extends StatefulWidget {
  const ScheduleTab({super.key, required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;
  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  late String _date = widget.desk.today;
  String? _clin;

  @override
  Widget build(BuildContext context) {
    final setup = widget.setup, desk = widget.desk, c = CfColors.of(context), t = Theme.of(context).textTheme;
    final clins = visibleClinicians(setup, desk);
    if (clins.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('No clinicians yet. Add them on the staff website.'), textAlign: TextAlign.center, style: t.bodyMedium)));
    }
    final cl = clins.where((x) => x.id == _clin).firstOrNull ?? clins.first;
    final day = desk.on(_date).where((a) => a.clinicianId == cl.id && a.status != ApptStatus.cancelled).toList();
    final cap = desk.capacity(cl, _date), booked = desk.booked(cl, _date);
    void shift(int n) => setState(() => _date = isoDate(DateTime.parse(_date).add(Duration(days: n))));

    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
      Row(children: [
        Expanded(child: Text(tr('Schedule'), style: t.headlineMedium?.copyWith(fontSize: 30))),
        IconButton.outlined(tooltip: tr('Previous day'), onPressed: () => shift(-1), icon: const Icon(Icons.chevron_left)),
        const SizedBox(width: 6),
        IconButton.outlined(tooltip: tr('Next day'), onPressed: () => shift(1), icon: const Icon(Icons.chevron_right)),
      ]),
      Row(children: [
        Text(longDay(_date, desk.today, lang: lang), style: t.bodyMedium?.copyWith(color: c.muted)),
        if (_date != desk.today) TextButton(onPressed: () => setState(() => _date = desk.today), child: Text(tr('Today'))),
      ]),
      if (clins.length > 1) ...[
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final x in clins)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(x.short.isEmpty ? x.name : x.short),
                  selected: x.id == cl.id,
                  showCheckmark: false,
                  selectedColor: Portal.navy,
                  labelStyle: TextStyle(color: x.id == cl.id ? Colors.white : c.fg, fontWeight: FontWeight.w500),
                  side: BorderSide(color: x.id == cl.id ? Portal.navy : c.line),
                  onSelected: (_) => setState(() => _clin = x.id),
                ),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      // the day in two figures, side by side with a line between
      Container(
        decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: c.line))),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _figure(context, tr('Booked'), '$booked', tr('of {cap} times', {'cap': cap}))),
            VerticalDivider(width: 1, color: c.line),
            Expanded(child: Padding(padding: const EdgeInsets.only(left: 16), child: _figure(context, tr('Open'), '${(cap - booked).clamp(0, 99)}', cap == 0 ? tr('not working') : tr('times left')))),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      for (final m in slotMinutes) _slot(context, cl, m, day.where((a) => a.minute == m).firstOrNull),
    ]);
  }

  Widget _figure(BuildContext context, String label, String value, String sub) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.bodyMedium),
        Text(value, style: t.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
        Text(sub, style: t.bodySmall),
      ]),
    );
  }

  Widget _slot(BuildContext context, SetupClinician cl, int m, DeskAppt? a) {
    final setup = widget.setup, desk = widget.desk, c = CfColors.of(context), t = Theme.of(context).textTheme;
    if (a != null) return VisitRow(setup: setup, desk: desk, appt: a, showActions: _date == desk.today);
    final why = desk.unavailable(cl, m, _date), held = desk.heldBy(cl.id, _date, m) != null, past = desk.clock.passed(_date, m);
    final label = why != null ? tr(why) : held ? tr('Held while someone books') : past ? tr('Not booked') : tr('Open');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(children: [
        SizedBox(width: 74, child: Text(formatTime(m, lang: lang), style: t.bodyMedium?.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]))),
        Text(label, style: t.bodyMedium?.copyWith(color: why == null && !held && !past ? c.good : c.muted, fontStyle: why != null ? FontStyle.italic : null)),
      ]),
    );
  }
}
