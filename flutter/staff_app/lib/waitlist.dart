import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'portal_theme.dart';
import 'ui.dart';

/// Times freed by cancellations and the people waiting for an earlier visit.
/// Cancelled times are offered automatically; the desk can also offer one by hand.
class WaitlistTab extends StatelessWidget {
  const WaitlistTab({super.key, required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;

  int get _hold => (setup.clinic['rules']?['offerHoldMinutes'] as int?) ?? 15;
  String _slot(String date, int minute) => '${dayLabel(date, desk.today, lang: lang)}, ${formatTime(minute, lang: lang)}';

  Future<void> _offer(BuildContext context, FreedSlot f) async {
    final fits = desk.waitlist.where((w) => !w.offerLive && w.fits(f.clinicianId, f.date, f.minute)).toList()
      ..sort((a, b) => a.priority != b.priority ? (a.priority ? -1 : 1) : a.joinedAt.compareTo(b.joinedAt));
    final pick = await showModalBottomSheet<WaitlistEntry>(
      context: context,
      builder: (context) {
        final t = Theme.of(context).textTheme;
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(tr('Offer {time} with {clinician}', {'time': _slot(f.date, f.minute), 'clinician': clinicianShort(setup, f.clinicianId)}), style: t.titleMedium),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(tr('Held for them for {minutes} minutes.', {'minutes': _hold}), style: t.bodySmall)),
            for (final w in fits)
              ListTile(
                title: Text(w.name),
                subtitle: Text(tr('Booked now: {when}', {'when': _slot(w.date, w.minute)})),
                trailing: w.priority ? Pill(tr('Priority'), tone: Tone.info) : null,
                onTap: () => Navigator.pop(context, w),
              ),
            if (fits.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), child: Text(tr('Nobody on the waitlist can come at that time.'), style: t.bodyMedium)),
          ]),
        );
      },
    );
    if (pick == null || !context.mounted) return;
    await act(context, () => desk.offer(f, pick, _hold), done: tr('Offered to {name}. Held for them for {minutes} minutes.', {'name': pick.name, 'minutes': _hold}));
  }

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final freed = desk.freed;
    final waiting = [...desk.waitlist]..sort((a, b) => a.priority != b.priority ? (a.priority ? -1 : 1) : a.joinedAt.compareTo(b.joinedAt));
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
      Row(children: [
        Expanded(child: Text(tr('Waitlist'), style: t.headlineMedium?.copyWith(fontSize: 30))),
        Pill(trn(waiting.length, '{n} waiting', '{n} waiting'), tone: Tone.info),
      ]),
      SectionHead(tr('Freed times'), count: freed.length),
      for (final f in freed)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_slot(f.date, f.minute)} · ${clinicianShort(setup, f.clinicianId)}', style: t.bodyLarge?.copyWith(color: c.fg, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                f.refilledBy != null
                    ? Pill(tr('Refilled by {name}', {'name': f.refilledBy}), tone: Tone.good)
                    : f.offeredTo != null
                        ? Pill(tr('Offered to {name}', {'name': f.offeredTo!.name}), tone: Tone.warn)
                        : Pill(tr('Open online'), tone: Tone.mute),
              ]),
            ),
            if (f.open && desk.me.runsDay) small(tr('Offer'), () => _offer(context, f), primary: true),
          ]),
        ),
      if (freed.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(tr('No cancelled times ahead.'), style: t.bodySmall)),
      SectionHead(tr('On the waitlist'), count: waiting.length),
      for (final w in waiting)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(w.name, style: t.bodyLarge?.copyWith(color: c.fg, fontWeight: FontWeight.w600))),
                  if (w.offerLive) ...[const SizedBox(width: 8), Pill(tr('Offered'), tone: Tone.warn)],
                ]),
                const SizedBox(height: 2),
                Text(tr('Booked now: {when}', {'when': _slot(w.date, w.minute)}), style: t.bodySmall),
                Text('${w.days.map(tr).join(', ')} · ${w.parts.map((p) => tr(p.label)).join(', ')}${w.clinicianId == null ? '' : ' · ${clinicianShort(setup, w.clinicianId!)}'}', style: t.bodySmall),
              ]),
            ),
            Column(children: [
              Text(tr('Priority'), style: t.labelSmall?.copyWith(color: c.muted)),
              Switch(
                value: w.priority,
                activeTrackColor: Portal.navy,
                onChanged: desk.me.runsDay
                    ? (v) => act(context, () => desk.setPriority(w, v), done: v ? tr('{name} gets offers first', {'name': w.name}) : tr('{name} back in joining order', {'name': w.name}))
                    : null,
              ),
            ]),
          ]),
        ),
      if (waiting.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(tr('Nobody is on the waitlist.'), style: t.bodySmall)),
      const SizedBox(height: 14),
      Text(tr('Offers go to priority patients first, then in the order they joined. Rules are set on the staff website.'), style: t.bodySmall),
    ]);
  }
}
