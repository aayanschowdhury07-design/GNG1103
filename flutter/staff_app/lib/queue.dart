import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'portal_theme.dart';
import 'ui.dart';

/// Who's here: the people in the clinic now (in the room, waiting, just checked in), then
/// who's still to arrive, by time. Clinicians see only their own patients.
class QueueTab extends StatefulWidget {
  const QueueTab({super.key, required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;
  @override
  State<QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends State<QueueTab> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final setup = widget.setup, desk = widget.desk, c = CfColors.of(context), t = Theme.of(context).textTheme;
    final own = desk.me.role == 'clinician';
    final clins = visibleClinicians(setup, desk).where((cl) => desk.capacity(cl, desk.today) > 0 || desk.todayVisits.any((a) => a.clinicianId == cl.id)).toList();
    final filter = own ? (desk.me.clinicianId ?? '') : _filter;
    final list = desk.todayVisits.where((a) => (filter == 'all' || a.clinicianId == filter) && a.status != ApptStatus.cancelled).toList();
    const order = {ApptStatus.inVisit: 0, ApptStatus.waiting: 1, ApptStatus.checkedIn: 2};
    int tk(DeskAppt a) => int.tryParse((a.ticket ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0;
    final here = list.where((a) => order.containsKey(a.status)).toList()..sort((a, b) => order[a.status]!.compareTo(order[b.status]!) != 0 ? order[a.status]!.compareTo(order[b.status]!) : tk(a).compareTo(tk(b)));
    final toCome = list.where((a) => a.status.upcoming).toList()..sort((a, b) => a.minute.compareTo(b.minute));
    final done = list.where((a) => a.status == ApptStatus.complete || a.status == ApptStatus.noShow).toList()..sort((a, b) => a.minute.compareTo(b.minute));
    final late = toCome.where(desk.isLate).toList();
    final nextUp = here.where((a) => a.status == ApptStatus.waiting && canActOn(desk, a)).firstOrNull ?? here.where((a) => a.status == ApptStatus.checkedIn && canActOn(desk, a)).firstOrNull;
    final waiting = desk.todayVisits.where((a) => a.status == ApptStatus.waiting).length, inRoom = desk.todayVisits.where((a) => a.status == ApptStatus.inVisit).length;

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 96), children: [
        Text(longDay(desk.today, desk.today, lang: lang), style: t.bodyMedium?.copyWith(color: c.muted)),
        const SizedBox(height: 2),
        Row(children: [
          Expanded(child: Text(tr('Who’s here'), style: t.headlineMedium?.copyWith(fontSize: 30))),
          Pill(tr('{w} waiting · {r} in visit', {'w': waiting, 'r': inRoom}), tone: waiting > 0 ? Tone.warn : Tone.mute),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: c.good, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(tr('Live · updates on every screen'), style: t.bodySmall),
        ]),
        if (!own && clins.length > 1) ...[
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (id, label) in [('all', tr('All')), for (final cl in clins) (cl.id, cl.short.isEmpty ? cl.name : cl.short)])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _filter == id,
                    showCheckmark: false,
                    selectedColor: Portal.navy,
                    labelStyle: TextStyle(color: _filter == id ? Colors.white : c.fg, fontWeight: FontWeight.w500),
                    side: BorderSide(color: _filter == id ? Portal.navy : c.line),
                    onSelected: (_) => setState(() => _filter = id),
                  ),
                ),
            ]),
          ),
        ],
        if (late.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.critSoft, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(Icons.schedule, color: c.crit, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  late.length == 1
                      ? tr('{name} is {n} min late for {time} and not checked in.', {'name': late.first.patientName, 'n': desk.lateBy(late.first), 'time': formatTime(late.first.minute, lang: lang)})
                      : tr('{n} patients are late and not checked in.', {'n': late.length}),
                  style: t.bodyMedium?.copyWith(color: c.crit),
                ),
              ),
            ]),
          ),
        ],
        SectionHead(tr('Here now'), count: here.length),
        for (final a in here) VisitRow(setup: setup, desk: desk, appt: a, primary: a == nextUp),
        if (here.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(tr('No one has arrived yet.'), style: t.bodySmall)),
        SectionHead(tr('Still to arrive'), count: toCome.length),
        for (final a in toCome) VisitRow(setup: setup, desk: desk, appt: a),
        if (toCome.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(tr('Everyone booked today has arrived.'), style: t.bodySmall)),
        if (done.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(tr('Completed today ({n})', {'n': done.length}), style: t.titleMedium?.copyWith(fontSize: 16)),
              children: [for (final a in done) VisitRow(setup: setup, desk: desk, appt: a, showActions: false)],
            ),
          ),
      ]),
    );
  }
}

/// Adds a walk-in: books them into the next open time today and checks them in.
Future<void> addWalkIn(BuildContext context, ClinicSetup setup, ClinicDesk desk) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: _WalkIn(setup: setup, desk: desk)),
    );

class _WalkIn extends StatefulWidget {
  const _WalkIn({required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;
  @override
  State<_WalkIn> createState() => _WalkInState();
}

class _WalkInState extends State<_WalkIn> {
  final _name = TextEditingController(), _phone = TextEditingController();
  String? _service, _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// The soonest open time today with someone who offers [serviceId].
  (String, int)? _next(String serviceId) {
    final d = widget.desk, s = widget.setup;
    final svc = s.services.where((x) => x.id == serviceId).firstOrNull;
    if (svc == null) return null;
    (String, int)? best;
    for (final cl in s.clinicians.where((cl) => svc.clinicianIds.contains(cl.id))) {
      for (final m in slotMinutes) {
        if (m < d.nowMinute - 10 || d.taken(cl.id, d.today, m) || d.unavailable(cl, m, d.today) != null || d.heldBy(cl.id, d.today, m) != null) continue;
        if (best == null || m < best.$2) best = (cl.id, m);
        break;
      }
    }
    return best;
  }

  Future<void> _add() async {
    final d = widget.desk, digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final slot = _service == null ? null : _next(_service!);
    setState(() => _error = _name.text.trim().isEmpty
        ? tr('Enter the patient’s name.')
        : digits.length < 10
            ? tr('Enter a 10-digit mobile number, so they get the confirmation and reminders.')
            : _service == null
                ? tr('Choose a service.')
                : slot == null
                    ? tr('No open time left today for that service.')
                    : null);
    if (_error != null || slot == null) return;
    setState(() => _busy = true);
    try {
      if (!await d.hold(slot.$1, d.today, slot.$2)) {
        setState(() => _error = tr('That time was just taken. Try again.'));
        return;
      }
      final outcome = await d.book(name: _name.text, phone: digits, serviceId: _service!, clinicianId: slot.$1, date: d.today, minute: slot.$2);
      if (outcome != BookingOutcome.booked) {
        setState(() => _error = tr('That time was just taken. Try again.'));
        return;
      }
      // the booking arrives on the desk a moment later; check them in once it's there
      DeskAppt? appt;
      for (var i = 0; i < 20 && appt == null; i++) {
        appt = d.todayVisits.where((a) => a.clinicianId == slot.$1 && a.minute == slot.$2 && a.status.upcoming).firstOrNull;
        if (appt == null) await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (appt != null) await d.setStatus(appt, ApptStatus.checkedIn);
      if (!mounted) return;
      Navigator.pop(context);
      say(context, tr('{name} added as a walk-in at {time} with {clinician}', {'name': _name.text.trim().split(' ').first, 'time': formatTime(slot.$2, lang: lang), 'clinician': clinicianShort(widget.setup, slot.$1)}));
    } catch (e) {
      setState(() => _error = tr('Couldn’t book: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.setup, c = CfColors.of(context), t = Theme.of(context).textTheme;
    final services = s.services.where((x) => x.clinicianIds.isNotEmpty).toList();
    final slot = _service == null ? null : _next(_service!);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Add a walk-in'), style: t.titleLarge),
          const SizedBox(height: 4),
          Text(tr('They’re booked into the next open time today and checked in.'), style: t.bodySmall),
          const SizedBox(height: 16),
          TextField(controller: _name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Full name'))),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Mobile number'))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _service,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Service')),
            items: [for (final x in services) DropdownMenuItem(value: x.id, child: Text('${x.name} · ${x.minutes} min', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() {
              _service = v;
              _error = null;
            }),
          ),
          if (_service != null) ...[
            const SizedBox(height: 10),
            Text(
              slot == null ? tr('No open time left today for that service.') : tr('Next open time: {time} with {clinician}', {'time': formatTime(slot.$2, lang: lang), 'clinician': clinicianShort(s, slot.$1)}),
              style: t.bodyMedium?.copyWith(color: slot == null ? c.warn : c.fg),
            ),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.crit))),
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _add, child: Text(tr('Add and check in'))),
        ]),
      ),
    );
  }
}
