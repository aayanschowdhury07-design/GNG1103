import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

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

    String when(WaitlistEntry w) => '${w.days.join('/')} · ${w.parts.map((p) => p.label.toLowerCase()).join(', ')}';
    String slot(String date, int minute) => '${dayLabel(date, desk.today)}, ${formatTime(minute)}';

    Future<void> offerTo(FreedSlot f) async {
      final fits = waiting.where((w) => !w.offerLive && w.fits(f.clinicianId, f.date, f.minute)).toList();
      final pick = await showDialog<WaitlistEntry>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('Offer ${slot(f.date, f.minute)} with ${clinicianShort(setup, f.clinicianId)}'),
          children: [
            if (fits.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), child: Text('Nobody on the waitlist can come then. The time stays open for online booking.', style: t.bodyMedium)),
            for (final w in fits)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, w),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(w.name, style: t.titleMedium),
                        Text('Now booked ${slot(w.date, w.minute)} · ${when(w)}', style: t.bodySmall),
                      ]),
                    ),
                    if (w.priority) const Pill('Priority', tone: Tone.crit),
                  ]),
                ),
              ),
            SimpleDialogOption(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        ),
      );
      if (pick == null || !context.mounted) return;
      await act(context, () => desk.offer(f, pick, _hold), done: 'Offered to ${pick.name}. Held for them for $_hold minutes.');
    }

    final rules = Map<String, dynamic>.from(setup.clinic['rules'] ?? const {});
    Widget rule(String key, String label, List<(int, String)> options) => SizedBox(
          width: 280,
          child: DropdownButtonFormField<int>(
            key: ValueKey('$key${rules[key]}'),
            initialValue: options.any((o) => o.$1 == rules[key]) ? rules[key] : null,
            decoration: InputDecoration(labelText: label),
            items: [for (final (v, l) in options) DropdownMenuItem(value: v, child: Text(l))],
            onChanged: desk.me.isAdmin
                ? (v) => act(context, () async {
                      await setup.setRule(key, v!);
                      await desk.record('settings.update', 'CLINIC', '$label: ${options.firstWhere((o) => o.$1 == v).$2}');
                    }, done: 'Saved')
                : null,
          ),
        );

    return PageFrame(
      eyebrow: 'Freed times are offered to the waitlist',
      title: 'Waitlist & recovery',
      children: [
        KpiRow(children: [
          Kpi(label: 'Freed times ahead', value: '${freed.length}', sub: freed.isEmpty ? 'no cancellations ahead' : '${freed.where((f) => f.open).length} still open'),
          Kpi(label: 'Refilled', value: '$refilled / ${freed.length}', sub: freed.isEmpty ? '—' : '${pct(refilled, freed.length)} recovery', tone: refilled > 0 ? Tone.good : null),
          Kpi(label: 'On the waitlist', value: '${waiting.length}', sub: '${waiting.where((w) => w.priority).length} flagged priority'),
        ]),
        Columns(flex: const [3, 2], children: [
          Panel(
            title: 'Freed times',
            note: 'Automatic offers start when Cloud Functions are on. Until then, offer each time from here.',
            child: SimpleTable(
              columns: const ['Time', 'Freed by', 'Status', ''],
              empty: 'No cancellations ahead.',
              rows: [
                for (final f in freed)
                  [
                    Text('${clinicianShort(setup, f.clinicianId)} · ${slot(f.date, f.minute)}', style: t.labelLarge),
                    Text(f.cancelled.cancelledBy == 'clinic' ? 'Clinic cancelled' : 'Patient cancelled', style: t.bodySmall),
                    f.refilledBy != null
                        ? Pill('Refilled · ${f.refilledBy}', tone: Tone.good)
                        : f.offeredTo != null
                            ? Pill('Offered to ${f.offeredTo!.name} · until ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(f.offeredTo!.offer!['expiresAt'])).format(context)}', tone: Tone.warn)
                            : const Pill('Open online'),
                    RowActions([if (f.open) small('Offer to…', () => offerTo(f), primary: true)]),
                  ],
              ],
            ),
          ),
          Panel(
            title: 'Rules',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              rule('cancelWindowHours', 'Free cancellation until', const [(12, '12 hours before'), (24, '24 hours before'), (48, '48 hours before')]),
              const SizedBox(height: 12),
              rule('offerHoldMinutes', 'An offer is held for', const [(15, '15 minutes'), (30, '30 minutes'), (60, '1 hour')]),
              const SizedBox(height: 12),
              rule('cutoffMinutes', 'Same-day online booking', const [(60, 'Up to 1 hour before'), (120, 'Up to 2 hours before'), (-1, 'Not allowed')]),
              const SizedBox(height: 8),
              Text(desk.me.isAdmin ? 'Offers go to priority patients first, then in the order they joined.' : 'Only an admin can change these rules.', style: t.bodySmall),
            ]),
          ),
        ]),
        Panel(
          title: 'On the waitlist',
          child: SimpleTable(
            columns: const ['Patient', 'Booked now', 'When they can come', 'Clinician', 'Joined', 'Status', 'Priority'],
            empty: 'Nobody is on the waitlist. Patients join from their visit in the app.',
            rows: [
              for (final w in waiting)
                [
                  Text(w.name, style: t.labelLarge),
                  Text('${slot(w.date, w.minute)} · ${setup.services.where((s) => s.id == w.serviceId).firstOrNull?.name ?? ''}', style: t.bodySmall),
                  Text(when(w), style: t.bodySmall),
                  Text(w.clinicianId == null ? 'Anyone' : clinicianShort(setup, w.clinicianId!), style: t.bodySmall),
                  Text(shortDate(isoDate(w.joinedAt)), style: t.bodySmall),
                  w.offerLive
                      ? const Pill('Offered', tone: Tone.warn)
                      : w.passed > 0
                          ? Pill('Passed ${w.passed}×')
                          : const Pill('Waiting'),
                  Switch(
                    value: w.priority,
                    onChanged: (v) => act(context, () => desk.setPriority(w, v), done: v ? '${w.name} gets offers first' : '${w.name} back in joining order'),
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
