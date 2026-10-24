import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

import '../scope.dart';
import '../widgets.dart';

/// "Get offered an earlier time": when the patient could come. If a matching slot frees up,
/// they get a push and a text first, and the slot is held for them for a short time.
class WaitlistScreen extends StatefulWidget {
  const WaitlistScreen({super.key});
  @override
  State<WaitlistScreen> createState() => _WaitlistScreenState();
}

class _WaitlistScreenState extends State<WaitlistScreen> {
  Set<String> _days = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri'};
  Set<DayPart> _parts = {DayPart.morning, DayPart.after4};
  String? _clinician; // null = any clinician
  bool _loaded = false;

  // start from the patient's saved preferences, once the backend is reachable
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final current = context.backend.myWaitlist();
    if (current != null) {
      _days = {...current.days};
      _parts = {...current.parts};
      _clinician = current.clinicianId;
    }
  }

  Future<void> _join() async {
    if (_days.isEmpty || _parts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick at least one day and one time of day.')));
      return;
    }
    await context.backend.joinWaitlist(WaitlistRequest(days: _days, parts: _parts, clinicianId: _clinician));
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You're on the waitlist. We'll text you first.")));
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => FilterChip(label: Text(label), selected: on, onSelected: (_) => setState(onTap), showCheckmark: false);

  @override
  Widget build(BuildContext context) {
    final b = context.backend;
    return ScreenFrame(
      title: 'Waitlist',
      bottom: FilledButton(onPressed: _join, child: const Text('Join waitlist')),
      children: [
        Text('Tell us when you can come. If a time opens, you get a push and a text first; the offer is held for you for ${b.offerHoldMinutes} minutes.',
            style: context.text.bodySmall),
        Section(
          title: 'Days',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in WaitlistRequest.weekdays) _chip(d, _days.contains(d), () => _days.contains(d) ? _days.remove(d) : _days.add(d)),
          ]),
        ),
        Section(
          title: 'Times',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in DayPart.values) _chip(p.label, _parts.contains(p), () => _parts.contains(p) ? _parts.remove(p) : _parts.add(p)),
          ]),
        ),
        Section(
          title: 'Clinician',
          child: UnderlineTabs<String?>(
            options: const [(null, 'Any'), ('osei', 'Dr. Osei only')],
            selected: _clinician,
            onSelect: (v) => setState(() => _clinician = v),
          ),
        ),
      ],
    );
  }
}

/// A freed slot held for this patient. Taking it moves their visit; passing sends it on.
class OfferScreen extends StatelessWidget {
  const OfferScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, c = context.colors, o = b.pendingOffer();
      final current = o == null ? null : b.myAppointments().where((a) => a.id == o.appointmentId).firstOrNull;
      final earlier = o != null && current != null && (o.date.compareTo(current.date) < 0 || (o.date == current.date && o.minute < current.minute));
      String when(String date, int minute) => '${dayLabel(date, b.today)}, ${formatTime(minute)}';
      Future<void> answer(bool take) async {
        take ? await b.acceptOffer() : await b.declineOffer();
        if (!context.mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(take ? 'The time is yours' : 'Kept your current time')));
      }

      return ScreenFrame(
        title: o == null ? 'This offer has ended' : earlier ? 'An earlier time opened' : 'A time opened up',
        children: [
          if (o != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: c.good, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(when(o.date, o.minute), style: context.text.headlineSmall?.copyWith(color: c.bg)),
                Text('${b.clinician(o.clinicianId).name} · ${b.clinic(b.clinician(o.clinicianId).clinicId).name}${current == null ? '' : ' · instead of ${when(current.date, current.minute)}'}',
                    style: context.text.bodyMedium?.copyWith(color: c.bg)),
                const SizedBox(height: 4),
                Text('Held for you for ${b.offerHoldMinutes} minutes', style: context.text.bodySmall?.copyWith(color: c.bg)),
              ]),
            ),
            const SizedBox(height: 12),
            Text("You're first in line for this time. If you pass, it goes to the next person on the list.", style: context.text.bodySmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => answer(true), child: const Text('Take this time')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => answer(false), child: const Text('Keep my current time')),
          ] else
            Text('Someone else took it, or the hold ran out. You stay on the waitlist.', style: context.text.bodyMedium),
        ],
      );
    });
  }
}
