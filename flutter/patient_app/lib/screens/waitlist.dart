import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

import '../scope.dart';
import '../widgets.dart';

/// "Get offered an earlier time": when the patient could come. If a matching slot frees up,
/// they get a push and a text first, and the slot is held for them for a short time.
class WaitlistScreen extends StatefulWidget {
  const WaitlistScreen({super.key, required this.appointmentId});

  /// The visit they'd like moved earlier; its clinician is offered as the "only" choice.
  final String appointmentId;
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
    final s = context.s;
    if (_days.isEmpty || _parts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('pickDayPart'))));
      return;
    }
    await context.backend.joinWaitlist(WaitlistRequest(days: _days, parts: _parts, clinicianId: _clinician));
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('onWaitlist'))));
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => FilterChip(label: Text(label), selected: on, onSelected: (_) => setState(onTap), showCheckmark: false);

  @override
  Widget build(BuildContext context) {
    final b = context.backend, s = context.s;
    final visit = b.myAppointments().where((a) => a.id == widget.appointmentId).firstOrNull;
    final mine = visit == null ? null : b.clinician(visit.clinicianId);
    return ScreenFrame(
      title: s.t('waitTitle'),
      bottom: FilledButton(onPressed: _join, child: Text(s.t('joinWaitlist'))),
      children: [
        Text(s.t('waitIntro', {'min': '${b.offerHoldMinutes}'}), style: context.text.bodySmall),
        Section(
          title: s.t('days'),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in WaitlistRequest.weekdays) _chip(s.weekday(d), _days.contains(d), () => _days.contains(d) ? _days.remove(d) : _days.add(d)),
          ]),
        ),
        Section(
          title: s.t('times'),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in DayPart.values) _chip(s.dayPart(p), _parts.contains(p), () => _parts.contains(p) ? _parts.remove(p) : _parts.add(p)),
          ]),
        ),
        if (mine != null)
          Section(
            title: s.t('clinicianWord'),
            child: UnderlineTabs<String?>(
              options: [(null, s.t('any')), (mine.id, s.t('only', {'name': mine.short}))],
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
      final b = context.backend, c = context.colors, s = context.s, lang = context.lang, o = b.pendingOffer();
      final current = o == null ? null : b.myAppointments().where((a) => a.id == o.appointmentId).firstOrNull;
      final earlier = o != null && current != null && (o.date.compareTo(current.date) < 0 || (o.date == current.date && o.minute < current.minute));
      String when(String date, int minute) => '${dayLabel(date, b.today, lang: lang)}, ${formatTime(minute, lang: lang)}';
      Future<void> answer(bool take) async {
        take ? await b.acceptOffer() : await b.declineOffer();
        if (!context.mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(take ? 'timeYours' : 'keptTime'))));
      }

      return ScreenFrame(
        title: s.t(o == null ? 'offerEnded' : earlier ? 'earlierOpened' : 'timeOpened'),
        children: [
          if (o != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: c.good, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(when(o.date, o.minute), style: context.text.headlineSmall?.copyWith(color: c.bg)),
                Text(
                  '${b.clinician(o.clinicianId).name} · ${b.clinic(b.clinician(o.clinicianId).clinicId).name}${current == null ? '' : ' · ${s.t('insteadOf', {'when': when(current.date, current.minute)})}'}',
                  style: context.text.bodyMedium?.copyWith(color: c.bg),
                ),
                const SizedBox(height: 4),
                Text(s.t('heldFor', {'min': '${b.offerHoldMinutes}'}), style: context.text.bodySmall?.copyWith(color: c.bg)),
              ]),
            ),
            const SizedBox(height: 12),
            Text(s.t('firstInLine'), style: context.text.bodySmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => answer(true), child: Text(s.t('takeTime'))),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => answer(false), child: Text(s.t('keepTime'))),
          ] else
            Text(s.t('offerGone'), style: context.text.bodyMedium),
        ],
      );
    });
  }
}
