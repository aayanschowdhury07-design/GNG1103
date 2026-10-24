import 'dart:async';

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../ui.dart';
import '../visit.dart';

enum CalView { day, week, month }

/// The clinic's calendar: a day grid with one column per clinician, a week of totals, or a month.
/// The front desk books callers from here with the same hold-then-book path patients use online.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.setup, required this.desk, this.startBooking = false});
  final ClinicSetup setup;
  final ClinicDesk desk;
  final bool startBooking;
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late String _date = widget.desk.today;
  CalView _view = CalView.day;
  _Booking? _booking;

  ClinicDesk get desk => widget.desk;
  ClinicSetup get setup => widget.setup;
  bool get canBook => desk.me.runsDay;

  /// Bookings go on the day shown, or today when looking back at a past day.
  String get _bookingDay => _date.compareTo(desk.today) < 0 ? desk.today : _date;

  @override
  void initState() {
    super.initState();
    if (widget.startBooking && canBook) _booking = _Booking(date: _bookingDay);
  }

  @override
  void dispose() {
    _booking?.release(desk);
    super.dispose();
  }

  void _goTo(String date) {
    setState(() => _date = date);
    // a booking in progress follows the day on show
    final b = _booking;
    if (b != null && b.date != _bookingDay) {
      b.release(desk);
      b
        ..date = _bookingDay
        ..error = null;
    }
  }

  void _shift(int n) {
    final d = DateTime.parse(_date);
    _goTo(n == 0
        ? desk.today
        : isoDate(switch (_view) {
            CalView.day => d.add(Duration(days: n)),
            CalView.week => d.add(Duration(days: 7 * n)),
            CalView.month => DateTime(d.year, d.month + n, 1),
          }));
  }

  void _openDay(String date) {
    _view = CalView.day;
    _goTo(date);
  }

  void _book({String? clinicianId, int? minute}) {
    _booking?.release(desk);
    setState(() => _booking = _Booking(clinicianId: clinicianId, date: _bookingDay));
    if (clinicianId != null && minute != null) _booking!.pick(desk, clinicianId, minute, () => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = DateTime.parse(_date);
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final title = switch (_view) {
      CalView.day => longDay(_date, desk.today),
      CalView.week => 'Week of ${shortDate(isoDate(monday))}',
      CalView.month => '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][d.month - 1]} ${d.year}',
    };
    return PageFrame(
      eyebrow: title,
      title: 'Calendar',
      actions: [
        IconButton.outlined(tooltip: 'Previous', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
        OutlinedButton(style: smallButton, onPressed: () => _shift(0), child: const Text('Today')),
        IconButton.outlined(tooltip: 'Next', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        SegmentedButton<CalView>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: CalView.day, label: Text('Day')), ButtonSegment(value: CalView.week, label: Text('Week')), ButtonSegment(value: CalView.month, label: Text('Month'))],
          selected: {_view},
          onSelectionChanged: (v) => setState(() => _view = v.first),
        ),
        if (canBook) FilledButton(style: smallFilled, onPressed: () => _book(), child: const Text('+ Book')),
      ],
      children: [
        if (_booking != null)
          _BookingPanel(
            setup: setup,
            desk: desk,
            booking: _booking!,
            onChanged: () => setState(() {}),
            onClose: () {
              _booking?.release(desk);
              setState(() => _booking = null);
            },
          ),
        if (_view == CalView.day) ...[
          const _Legend(),
          Panel(padding: const EdgeInsets.all(12), child: _DayGrid(setup: setup, desk: desk, date: _date, onBook: canBook ? (c, m) => _book(clinicianId: c, minute: m) : null)),
          Text(
            _date.compareTo(desk.today) >= 0
                ? 'Choosing a time holds it while that person finishes (5 minutes online, 2 minutes at the front desk). Only one booking can exist per clinician and start time.'
                : 'A past day: what was recorded, as it happened.',
            style: t.bodySmall,
          ),
        ],
        if (_view == CalView.week) Panel(child: _Week(setup: setup, desk: desk, monday: monday, onOpen: _openDay)),
        if (_view == CalView.month) Panel(child: _Month(setup: setup, desk: desk, month: d, onOpen: _openDay)),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) => Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final s in const [ApptStatus.booked, ApptStatus.confirmed, ApptStatus.late, ApptStatus.checkedIn, ApptStatus.waiting, ApptStatus.inVisit, ApptStatus.complete]) StatusMark(s),
        const Pill('Freed slot', tone: Tone.good),
        const Pill('Held while someone books', tone: Tone.warn),
        const Pill('Unavailable'),
        Text('Outlined: not here yet. Filled: arrived.', style: Theme.of(context).textTheme.bodySmall),
      ]);
}

// ---------------------------------------------------------------- the day grid

class _DayGrid extends StatelessWidget {
  const _DayGrid({required this.setup, required this.desk, required this.date, this.onBook});
  final ClinicSetup setup;
  final ClinicDesk desk;
  final String date;
  final void Function(String clinicianId, int minute)? onBook;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final clins = visibleClinicians(setup, desk);
    if (clins.isEmpty) return Text('No clinicians yet. Add them under Services & clinicians.', style: t.bodySmall);
    final ahead = date.compareTo(desk.today) >= 0;
    return LayoutBuilder(builder: (context, box) {
      final colWidth = ((box.maxWidth - 80) / clins.length).clamp(150.0, 320.0);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 80 + colWidth * clins.length,
          child: Column(children: [
            Row(children: [
              const SizedBox(width: 80),
              for (final cl in clins)
                SizedBox(
                  width: colWidth,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cl.short.isEmpty ? cl.name : cl.short, style: t.labelLarge),
                      Text(cl.role, style: t.bodySmall, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
            ]),
            for (final m in slotMinutes)
              Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                child: Row(children: [
                  SizedBox(
                    width: 80,
                    child: Text(formatTime(m), style: t.bodySmall?.copyWith(color: desk.clock.passed(date, m + 30) ? c.lineStrong : c.muted, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                  for (final cl in clins) SizedBox(width: colWidth, height: 52, child: Padding(padding: const EdgeInsets.all(3), child: _cell(context, cl, m, ahead))),
                ]),
              ),
          ]),
        ),
      );
    });
  }

  Widget _cell(BuildContext context, SetupClinician cl, int m, bool ahead) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final a = desk.on(date).where((a) => a.clinicianId == cl.id && a.minute == m && a.active).firstOrNull;
    if (a != null) {
      final s = shownStatus(desk, a), color = c.statusColor(s);
      return Semantics(
        button: true,
        label: '${a.patientName}, ${formatTime(m)}, ${s.label}',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => showVisit(context, setup, desk, a.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: s.arrived ? color.withValues(alpha: .14) : c.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: color, width: 3), top: BorderSide(color: c.line), right: BorderSide(color: c.line), bottom: BorderSide(color: c.line)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(a.patientName, style: t.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${s.label} · ${setup.services.where((x) => x.id == a.serviceId).firstOrNull?.minutes ?? 30} min', style: t.labelMedium?.copyWith(color: color), maxLines: 1),
            ]),
          ),
        ),
      );
    }
    final off = desk.unavailable(cl, m, date);
    if (off != null) return _flat(context, off, c.surface2, c.muted);
    if (ahead) {
      final held = desk.heldBy(cl.id, date, m);
      if (held != null) return _flat(context, held == 'desk' ? 'Held · front desk' : 'Held · patient online', c.warnSoft, c.warn, icon: Icons.lock_outline);
      final f = desk.freed.where((f) => f.clinicianId == cl.id && f.date == date && f.minute == m).firstOrNull;
      if (f != null && desk.me.runsDay) return _flat(context, f.offeredTo != null ? 'Freed · offered' : 'Freed · open', c.goodSoft, c.good);
      // a time that has already started can't be booked
      if (desk.clock.passed(date, m)) return const SizedBox.shrink();
      if (onBook != null && !desk.taken(cl.id, date, m)) {
        return Semantics(
          button: true,
          label: 'Book ${cl.short} at ${formatTime(m)}',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onBook!(cl.id, m),
            child: Container(alignment: Alignment.center, decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: c.line)), child: Icon(Icons.add, size: 18, color: c.muted)),
          ),
        );
      }
    }
    return const SizedBox.shrink();
  }

  Widget _flat(BuildContext context, String label, Color bg, Color fg, {IconData? icon}) => Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          if (icon != null) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(icon, size: 14, color: fg)),
          Flexible(child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg), overflow: TextOverflow.ellipsis)),
        ]),
      );
}

// ---------------------------------------------------------------- week and month

class _Week extends StatelessWidget {
  const _Week({required this.setup, required this.desk, required this.monday, required this.onOpen});
  final ClinicSetup setup;
  final ClinicDesk desk;
  final DateTime monday;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final days = [for (var i = 0; i < 6; i++) isoDate(monday.add(Duration(days: i)))];
    return SimpleTable(
      columns: ['Clinician', for (final d in days) shortDate(d).split(' ').first + (d == desk.today ? ' (today)' : '')],
      rows: [
        [const SizedBox.shrink(), for (final d in days) TextButton(onPressed: () => onOpen(d), child: Text(shortDate(d).substring(4)))],
        for (final cl in visibleClinicians(setup, desk))
          [
            Text(cl.short.isEmpty ? cl.name : cl.short, style: t.labelLarge),
            for (final d in days)
              Builder(builder: (context) {
                final cap = desk.capacity(cl, d), n = desk.booked(cl, d);
                if (cap == 0 && n == 0) return Text('Not in', style: t.bodySmall);
                return SizedBox(
                  width: 90,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$n / $cap', style: t.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: cap == 0 ? 0 : n / cap, minHeight: 6, backgroundColor: c.surface2, color: c.accent, borderRadius: BorderRadius.circular(3)),
                  ]),
                );
              }),
          ],
      ],
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({required this.setup, required this.desk, required this.month, required this.onOpen});
  final ClinicSetup setup;
  final ClinicDesk desk;
  final DateTime month;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final first = DateTime(month.year, month.month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final clins = visibleClinicians(setup, desk);
    return Column(children: [
      Row(children: [for (final d in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) Expanded(child: Padding(padding: const EdgeInsets.all(6), child: Text(d, style: t.labelMedium?.copyWith(color: c.muted))))]),
      for (var w = 0; w < 6; w++)
        Row(children: [
          for (var i = 0; i < 7; i++)
            Builder(builder: (context) {
              final day = start.add(Duration(days: w * 7 + i)), iso = isoDate(day);
              final inMonth = day.month == month.month;
              final open = clins.any((cl) => desk.capacity(cl, iso) > 0);
              final n = clins.fold<int>(0, (s, cl) => s + desk.booked(cl, iso));
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onOpen(iso),
                    child: Container(
                      height: 64,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: iso == desk.today ? c.accentSoft : null,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: iso == desk.today ? c.accent : c.line),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${day.day}', style: t.labelLarge?.copyWith(color: inMonth ? c.fg : c.lineStrong)),
                        const Spacer(),
                        Text(!open && n == 0 ? 'Closed' : '$n booked', style: t.bodySmall?.copyWith(color: inMonth ? c.muted : c.lineStrong)),
                      ]),
                    ),
                  ),
                ),
              );
            }),
        ]),
    ]);
  }
}

// ---------------------------------------------------------------- booking at the front desk

/// A booking in progress: who, what, the day, and the time being held for it.
class _Booking {
  _Booking({this.clinicianId, required this.date});
  String? clinicianId, serviceId, error;
  String date;
  int? minute;
  DateTime? heldUntil;
  bool busy = false;

  Future<void> pick(ClinicDesk desk, String clinicianId, int? m, VoidCallback changed) async {
    await release(desk);
    this.clinicianId = clinicianId;
    minute = null;
    error = null;
    changed();
    if (m == null) return;
    if (await desk.hold(clinicianId, date, m)) {
      minute = m;
      heldUntil = DateTime.now().add(const Duration(minutes: 2));
    } else {
      error = '${formatTime(m)} is being booked online by a patient right now. Pick another time or wait for their hold to run out.';
    }
    changed();
  }

  Future<void> release(ClinicDesk desk) async {
    if (clinicianId != null && minute != null) await desk.release(clinicianId!, date, minute!);
    minute = null;
    heldUntil = null;
  }
}

/// "10:30 am is held for you for 1:42". Ticks on its own, so the form around it isn't rebuilt
/// every second while someone types.
class _HoldCountdown extends StatefulWidget {
  const _HoldCountdown({super.key, required this.minute, required this.until, required this.onExpired});
  final int minute;
  final DateTime until;
  final VoidCallback onExpired;
  @override
  State<_HoldCountdown> createState() => _HoldCountdownState();
}

class _HoldCountdownState extends State<_HoldCountdown> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.until.isBefore(DateTime.now())) {
        _tick.cancel();
        widget.onExpired();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), left = widget.until.difference(DateTime.now());
    final s = left.isNegative ? Duration.zero : left;
    return Row(children: [
      Icon(Icons.lock_outline, size: 16, color: c.warn),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          '${formatTime(widget.minute)} is held for you for ${s.inMinutes}:${(s.inSeconds % 60).toString().padLeft(2, '0')}. Nobody can book it online meanwhile.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.warn),
        ),
      ),
    ]);
  }
}

class _BookingPanel extends StatefulWidget {
  const _BookingPanel({required this.setup, required this.desk, required this.booking, required this.onChanged, required this.onClose});
  final ClinicSetup setup;
  final ClinicDesk desk;
  final _Booking booking;
  final VoidCallback onChanged, onClose;
  @override
  State<_BookingPanel> createState() => _BookingPanelState();
}

class _BookingPanelState extends State<_BookingPanel> {
  final _name = TextEditingController(), _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final b = widget.booking, d = widget.desk;
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    b.error = _name.text.trim().isEmpty
        ? 'Enter the patient’s name.'
        : digits.length < 10
            ? 'Enter a 10-digit mobile number, so they get the confirmation and reminders.'
            : b.serviceId == null || b.clinicianId == null || b.minute == null
                ? 'Choose a service, a clinician and a time.'
                : null;
    if (b.error != null) return widget.onChanged();
    setState(() => b.busy = true);
    try {
      final outcome = await d.book(name: _name.text, phone: digits, serviceId: b.serviceId!, clinicianId: b.clinicianId!, date: b.date, minute: b.minute!);
      if (!mounted) return;
      switch (outcome) {
        case BookingOutcome.booked:
          say(context, 'Booked ${_name.text.trim()} for ${dayLabel(b.date, d.today, midSentence: true)} at ${formatTime(b.minute!)} with ${clinicianShort(widget.setup, b.clinicianId!)}. Confirmation text queued.');
          b.minute = null;
          widget.onClose();
          return;
        case BookingOutcome.slotTaken:
          b.error = 'That time was taken a moment ago. Pick another time.';
        case BookingOutcome.holdExpired:
          b.error = 'Your hold on ${formatTime(b.minute!)} ran out. Pick the time again.';
      }
      b.minute = null;
    } catch (e) {
      b.error = 'Couldn’t book: $e';
    } finally {
      b.busy = false;
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.setup, d = widget.desk, b = widget.booking, c = CfColors.of(context), t = Theme.of(context).textTheme;
    final services = s.services.where((x) => x.clinicianIds.isNotEmpty).toList();
    b.serviceId ??= services.where((x) => b.clinicianId == null || x.clinicianIds.contains(b.clinicianId)).firstOrNull?.id;
    final svc = services.where((x) => x.id == b.serviceId).firstOrNull;
    final clins = s.clinicians.where((cl) => svc == null || svc.clinicianIds.contains(cl.id)).toList();
    if (b.clinicianId != null && !clins.any((cl) => cl.id == b.clinicianId)) b.clinicianId = null;
    b.clinicianId ??= clins.firstOrNull?.id;
    final cl = clins.where((x) => x.id == b.clinicianId).firstOrNull;
    final free = cl == null
        ? <int>[]
        : slotMinutes
            .where((m) => m == b.minute || (!d.clock.passed(b.date, m) && !d.taken(cl.id, b.date, m) && d.unavailable(cl, m, b.date) == null && d.heldBy(cl.id, b.date, m) == null))
            .toList();
    return Panel(
      title: 'New booking (front desk)',
      trailing: TextButton(onPressed: widget.onClose, child: const Text('Close')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(width: 220, child: TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Patient name'))),
          SizedBox(width: 180, child: TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number'))),
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              key: ValueKey('svc${b.serviceId}'),
              initialValue: b.serviceId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Service'),
              items: [for (final x in services) DropdownMenuItem(value: x.id, child: Text('${x.name} · ${x.minutes} min', overflow: TextOverflow.ellipsis))],
              onChanged: (v) async {
                await b.release(d);
                b.serviceId = v;
                b.error = null;
                widget.onChanged();
              },
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              key: ValueKey('cl${b.clinicianId}${b.serviceId}'),
              initialValue: b.clinicianId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Clinician'),
              items: [for (final x in clins) DropdownMenuItem(value: x.id, child: Text(x.short.isEmpty ? x.name : x.short))],
              onChanged: (v) => b.pick(d, v!, null, widget.onChanged),
            ),
          ),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<int>(
              key: ValueKey('t${b.clinicianId}${b.date}${b.minute}${free.length}'),
              initialValue: b.minute,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Time, ${dayLabel(b.date, d.today, midSentence: true)}'),
              items: [for (final m in free) DropdownMenuItem(value: m, child: Text(formatTime(m)))],
              onChanged: (v) => b.pick(d, b.clinicianId!, v, widget.onChanged),
            ),
          ),
          FilledButton(onPressed: b.busy ? null : _confirm, child: const Text('Book')),
        ]),
        const SizedBox(height: 10),
        if (b.minute != null && b.heldUntil != null)
          _HoldCountdown(
            key: ValueKey(b.heldUntil),
            minute: b.minute!,
            until: b.heldUntil!,
            onExpired: () {
              b.minute = null;
              b.error = 'Your 2-minute hold ran out. Pick the time again.';
              widget.onChanged();
            },
          ),
        if (b.error != null) Text(b.error!, style: t.bodyMedium?.copyWith(color: c.crit, fontWeight: FontWeight.w500)),
        if (cl != null)
          Text('${free.where((m) => m != b.minute).length} open times with ${cl.short.isEmpty ? cl.name : cl.short} ${b.date == d.today ? 'today' : 'on ${shortDate(b.date)}'}. Change the day with the calendar’s arrows.',
              style: t.bodySmall),
        if (services.isEmpty) Text('No service has a clinician yet. Assign clinicians under Services & clinicians.', style: t.bodySmall?.copyWith(color: c.warn)),
      ]),
    );
  }
}
