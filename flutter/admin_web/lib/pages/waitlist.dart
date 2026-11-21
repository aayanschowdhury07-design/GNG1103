import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../ui.dart';
import '../visit.dart';

/// Times freed by cancellations, who they were offered to, and the people waiting.
class WaitlistPage extends StatelessWidget {
  const WaitlistPage({super.key, required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;

  int get _hold => (setup.clinic['rules']?['offerHoldMinutes'] as int?) ?? 15;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    final freed = desk.freed;
    final refilled = freed.where((f) => f.refilledBy != null).length;
    final waiting = desk.waitlist;

    String when(WaitlistEntry w) => '${w.days.map(tr).join('/')} · ${w.parts.map((p) => tr(p.label).toLowerCase()).join(', ')}';
    String slot(String date, int minute) => '${dayLabel(date, desk.today, lang: lang)}, ${formatTime(minute, lang: lang)}';

    Future<void> offerTo(FreedSlot f) async {
      final fits = waiting.where((w) => !w.offerLive && w.fits(f.clinicianId, f.date, f.minute)).toList();
      final pick = await showDialog<WaitlistEntry>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(tr('Offer {time} with {clinician}', {'time': slot(f.date, f.minute), 'clinician': clinicianShort(setup, f.clinicianId)})),
          children: [
            if (fits.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), child: Text(tr('Nobody on the waitlist can come then. The time stays open for online booking.'), style: t.bodyMedium)),
            for (final w in fits)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, w),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(w.name, style: t.titleMedium),
                        Text(tr('Now booked {time} · {when}', {'time': slot(w.date, w.minute), 'when': when(w)}), style: t.bodySmall),
                      ]),
                    ),
                    if (w.priority) Pill(tr('Priority'), tone: Tone.crit),
                  ]),
                ),
              ),
            SimpleDialogOption(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          ],
        ),
      );
      if (pick == null || !context.mounted) return;
      await act(context, () => desk.offer(f, pick, _hold), done: tr('Offered to {name}. Held for them for {minutes} minutes.', {'name': pick.name, 'minutes': _hold}));
    }

    final rules = Map<String, dynamic>.from(setup.clinic['rules'] ?? const {});
    Widget rule(String key, String label, List<(int, String)> options) => SizedBox(
          width: 280,
          child: DropdownButtonFormField<int>(
            key: ValueKey('$key${rules[key]}'),
            initialValue: options.any((o) => o.$1 == rules[key]) ? rules[key] : null,
            decoration: InputDecoration(labelText: tr(label)),
            items: [for (final (v, l) in options) DropdownMenuItem(value: v, child: Text(tr(l)))],
            onChanged: desk.me.isAdmin
                ? (v) => act(context, () async {
                      await setup.setRule(key, v!);
                      await desk.record('settings.update', 'CLINIC', '$label: ${options.firstWhere((o) => o.$1 == v).$2}');
                    }, done: tr('Saved'))
                : null,
          ),
        );

    return PageFrame(
      title: tr('Waitlist & recovery'),
      children: [
        KpiRow(children: [
          Kpi(label: tr('Freed times ahead'), value: '${freed.length}', sub: freed.isEmpty ? tr('no cancellations ahead') : tr('{n} still open', {'n': freed.where((f) => f.open).length})),
          Kpi(label: tr('Refilled'), value: '$refilled / ${freed.length}', sub: freed.isEmpty ? '—' : tr('{pct} recovery', {'pct': pct(refilled, freed.length)}), tone: refilled > 0 ? Tone.good : null),
          Kpi(label: tr('On the waitlist'), value: '${waiting.length}', sub: tr('{n} flagged priority', {'n': waiting.where((w) => w.priority).length})),
        ]),
        Columns(flex: const [3, 2], children: [
          Panel(
            title: tr('Freed times'),
            child: SimpleTable(
              columns: [tr('Time'), tr('Freed by'), tr('Status'), ''],
              empty: tr('No cancellations ahead.'),
              rows: [
                for (final f in freed)
                  [
                    Text('${clinicianShort(setup, f.clinicianId)} · ${slot(f.date, f.minute)}', style: t.labelLarge),
                    Text(f.cancelled.cancelledBy == 'clinic' ? tr('Clinic cancelled') : tr('Patient cancelled'), style: t.bodySmall),
                    f.refilledBy != null
                        ? Pill(tr('Refilled · {by}', {'by': f.refilledBy}), tone: Tone.good)
                        : f.offeredTo != null
                            ? Pill(tr('Offered to {name} · until {time}', {'name': f.offeredTo!.name, 'time': TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(f.offeredTo!.offer!['expiresAt'])).format(context)}), tone: Tone.warn)
                            : Pill(tr('Open online')),
                    RowActions([if (f.open) small(tr('Offer to…'), () => offerTo(f), primary: true)]),
                  ],
              ],
            ),
          ),
          Panel(
            title: tr('Rules'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              rule('cancelWindowHours', 'Free cancellation until', const [(12, '12 hours before'), (24, '24 hours before'), (48, '48 hours before')]),
              const SizedBox(height: 12),
              rule('offerHoldMinutes', 'An offer is held for', const [(15, '15 minutes'), (30, '30 minutes'), (60, '1 hour')]),
              const SizedBox(height: 12),
              rule('cutoffMinutes', 'Same-day online booking', const [(60, 'Up to 1 hour before'), (120, 'Up to 2 hours before'), (-1, 'Not allowed')]),
              const SizedBox(height: 8),
              Text(desk.me.isAdmin ? tr('Offers go to priority patients first, then in the order they joined.') : tr('Only an admin can change these rules.'), style: t.bodySmall),
            ]),
          ),
        ]),
        Panel(
          title: tr('On the waitlist'),
          child: SimpleTable(
            columns: [tr('Patient'), tr('Booked now'), tr('When they can come'), tr('Clinician'), tr('Joined'), tr('Status'), tr('Priority')],
            empty: tr('Nobody is on the waitlist. Patients join from their visit in the app.'),
            rows: [
              for (final w in waiting)
                [
                  Text(w.name, style: t.labelLarge),
                  Text('${slot(w.date, w.minute)} · ${setup.services.where((s) => s.id == w.serviceId).firstOrNull?.name ?? ''}', style: t.bodySmall),
                  Text(when(w), style: t.bodySmall),
                  Text(w.clinicianId == null ? tr('Anyone') : clinicianShort(setup, w.clinicianId!), style: t.bodySmall),
                  Text(shortDate(isoDate(w.joinedAt), lang: lang), style: t.bodySmall),
                  w.offerLive
                      ? Pill(tr('Offered'), tone: Tone.warn)
                      : w.passed > 0
                          ? Pill(tr('Passed {n}×', {'n': w.passed}))
                          : Pill(tr('Waiting')),
                  Switch(
                    value: w.priority,
                    onChanged: (v) => act(context, () => desk.setPriority(w, v), done: v ? tr('{name} gets offers first', {'name': w.name}) : tr('{name} back in joining order', {'name': w.name})),
                    thumbIcon: WidgetStatePropertyAll(Icon(w.priority ? Icons.priority_high : null, size: 14, color: c.bg)),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}
