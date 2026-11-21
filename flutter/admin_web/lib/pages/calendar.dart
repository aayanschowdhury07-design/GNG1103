import 'dart:async';

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../portal_theme.dart';
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
    final d = DateTime.parse(_date);
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final title = switch (_view) {
      CalView.day => longDay(_date, desk.today, lang: lang),
      CalView.week => tr('Week of {date}', {'date': shortDate(isoDate(monday), lang: lang)}),
      CalView.month => '${tr(const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][d.month - 1])} ${d.year}',
    };
    if (_booking != null) {
      return PageFrame(
        title: tr('New booking'),
        eyebrow: tr('For a patient who calls or walks in.'),
        children: [
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
        ],
      );
    }
    return PageFrame(
      eyebrow: title,
      title: tr('Calendar'),
      actions: [
        IconButton.outlined(tooltip: tr('Previous'), onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
        OutlinedButton(style: smallButton, onPressed: () => _shift(0), child: Text(tr('Today'))),
        IconButton.outlined(tooltip: tr('Next'), onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        SegmentedButton<CalView>(
          showSelectedIcon: false,
          segments: [ButtonSegment(value: CalView.day, label: Text(tr('Day'))), ButtonSegment(value: CalView.week, label: Text(tr('Week'))), ButtonSegment(value: CalView.month, label: Text(tr('Month')))],
          selected: {_view},
          onSelectionChanged: (v) => setState(() => _view = v.first),
        ),
        if (canBook) FilledButton.icon(style: smallFilled, onPressed: () => _book(), icon: const Icon(Icons.add, size: 18), label: Text(tr('New booking'))),
      ],
      children: [
        if (_view == CalView.day) ...[
          const _Legend(),
          Panel(boxed: true, padding: const EdgeInsets.all(12), child: _DayGrid(setup: setup, desk: desk, date: _date, onBook: canBook ? (c, m) => _book(clinicianId: c, minute: m) : null)),
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
        for (final s in const [ApptStatus.booked, ApptStatus.confirmed, ApptStatus.late, ApptStatus.checkedIn, ApptStatus.waiting, ApptStatus.inVisit, ApptStatus.complete]) StatusMark(s, label: tr(s.label)),
        Pill(tr('Freed slot'), tone: Tone.good),
        Pill(tr('Held while someone books'), tone: Tone.warn),
        Pill(tr('Unavailable')),
        Text(tr('Outlined: not here yet. Filled: arrived.'),style: Theme.of(context).textTheme.bodySmall),
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
    if (clins.isEmpty) return Text(tr('No clinicians yet. Add them under Services & clinicians.'), style: t.bodySmall);
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
                    child: Text(formatTime(m, lang: lang), style: t.bodySmall?.copyWith(color: desk.clock.passed(date, m + 30) ? c.lineStrong : c.muted, fontFeatures: const [FontFeature.tabularFigures()])),
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
        label: '${a.patientName}, ${formatTime(m, lang: lang)}, ${tr(s.label)}',
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
              Text(tr('{status} · {n} min', {'status': tr(s.label), 'n': setup.services.where((x) => x.id == a.serviceId).firstOrNull?.minutes ?? 30}),style: t.labelMedium?.copyWith(color: color), maxLines: 1),
            ]),
          ),
        ),
      );
    }
    final off = desk.unavailable(cl, m, date);
    if (off != null) return _flat(context, tr(off), c.surface2, c.muted);
    if (ahead) {
      final held = desk.heldBy(cl.id, date, m);
      if (held != null) return _flat(context, held == 'desk' ? tr('Held · front desk') : tr('Held · patient online'), c.warnSoft, c.warn, icon: Icons.lock_outline);
      final f = desk.freed.where((f) => f.clinicianId == cl.id && f.date == date && f.minute == m).firstOrNull;
      if (f != null && desk.me.runsDay) return _flat(context, f.offeredTo != null ? tr('Freed · offered') : tr('Freed · open'), c.goodSoft, c.good);
      // a time that has already started can't be booked
      if (desk.clock.passed(date, m)) return const SizedBox.shrink();
      if (onBook != null && !desk.taken(cl.id, date, m)) {
        return Semantics(
          button: true,
          label: tr('Book {clinician} at {time}', {'clinician': cl.short, 'time': formatTime(m, lang: lang)}),
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
      columns: [tr('Clinician'), for (final d in days) shortDate(d, lang: lang).split(' ').first + (d == desk.today ? tr(' (today)') : '')],
      rows: [
        [const SizedBox.shrink(), for (final d in days) TextButton(onPressed: () => onOpen(d), child: Text(shortDate(d, lang: lang).substring(shortDate(d, lang: lang).indexOf(' ') + 1)))],
        for (final cl in visibleClinicians(setup, desk))
          [
            Text(cl.short.isEmpty ? cl.name : cl.short, style: t.labelLarge),
            for (final d in days)
              Builder(builder: (context) {
                final cap = desk.capacity(cl, d), n = desk.booked(cl, d);
                if (cap == 0 && n == 0) return Text(tr('Not in'), style: t.bodySmall);
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
      Row(children: [for (final d in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) Expanded(child: Padding(padding: const EdgeInsets.all(6), child: Text(tr(d), style: t.labelMedium?.copyWith(color: c.muted))))]),
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
                        Text(!open && n == 0 ? tr('Closed') : tr('{n} booked', {'n': n}),style: t.bodySmall?.copyWith(color: inMonth ? c.muted : c.lineStrong)),
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

  /// Which step is showing: 0 patient, 1 service, 2 day and time, 3 check and book.
  int step = 0;
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
      error = tr('{time} is being booked online by a patient right now. Pick another time or wait for their hold to run out.', {'time': formatTime(m, lang: lang)});
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
          tr('{time} is held for you for {left}. Nobody can book it online meanwhile.', {'time': formatTime(widget.minute, lang: lang), 'left': '${s.inMinutes}:${(s.inSeconds % 60).toString().padLeft(2, '0')}'}),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.warn),
        ),
      ),
    ]);
  }
}

/// New booking, in four steps: the patient, the service, the day and time, then a check.
/// The time is held (2 minutes) as soon as it's picked, the same hold patients get online.
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
  final _name = TextEditingController(), _phone = TextEditingController(), _find = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _phone, _find]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _find.dispose();
    super.dispose();
  }

  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');

  /// People the front desk booked before, newest first, one per phone number.
  List<(String, String)> get _known {
    final seen = <String>{}, out = <(String, String)>[];
    final all = [...widget.desk.appointments]..sort((a, b) => b.date == a.date ? b.minute - a.minute : b.date.compareTo(a.date));
    for (final a in all) {
      final ph = (a.phone ?? '').replaceAll(RegExp(r'\D'), '');
      if (ph.length < 10 || a.patientName.trim().isEmpty || !seen.add(ph)) continue;
      out.add((a.patientName.trim(), ph));
    }
    return out;
  }

  String _fmtPhone(String d) => d.length == 10 ? '(${d.substring(0, 3)}) ${d.substring(3, 6)}-${d.substring(6)}' : d;

  /// Why the current step can't go on yet, or null when it can.
  String? _blocked(_Booking b) => switch (b.step) {
        0 => _name.text.trim().isEmpty
            ? tr('Enter the patient’s name.')
            : _digits.length < 10
                ? tr('Enter a 10-digit mobile number, so they get the confirmation and reminders.')
                : null,
        1 => b.serviceId == null ? tr('Choose a service.') : null,
        2 => b.clinicianId == null || b.minute == null ? tr('Choose a time.') : null,
        _ => null,
      };

  void _next() {
    final b = widget.booking;
    b.error = _blocked(b);
    if (b.error == null) {
      if (b.step < 3) {
        b.step++;
      } else {
        _confirm();
        return;
      }
    }
    widget.onChanged();
  }

  void _back() {
    final b = widget.booking;
    b.error = null;
    b.step--;
    widget.onChanged();
  }

  Future<void> _confirm() async {
    final b = widget.booking, d = widget.desk;
    if (b.serviceId == null || b.clinicianId == null || b.minute == null) {
      b
        ..error = tr('Choose a service, a clinician and a time.')
        ..step = b.serviceId == null ? 1 : 2;
      return widget.onChanged();
    }
    setState(() => b.busy = true);
    try {
      final outcome = await d.book(name: _name.text, phone: _digits, serviceId: b.serviceId!, clinicianId: b.clinicianId!, date: b.date, minute: b.minute!);
      if (!mounted) return;
      switch (outcome) {
        case BookingOutcome.booked:
          say(context, tr('Booked {name} for {day} at {time} with {clinician}. Confirmation text queued.', {'name': _name.text.trim(), 'day': dayLabel(b.date, d.today, lang: lang, midSentence: true), 'time': formatTime(b.minute!, lang: lang), 'clinician': clinicianShort(widget.setup, b.clinicianId!)}));
          b.minute = null;
          widget.onClose();
          return;
        case BookingOutcome.slotTaken:
          b.error = tr('That time was taken a moment ago. Pick another time.');
        case BookingOutcome.holdExpired:
          b.error = tr('Your hold on {time} ran out. Pick the time again.', {'time': formatTime(b.minute!, lang: lang)});
      }
      b
        ..minute = null
        ..step = 2;
    } catch (e) {
      b.error = tr('Couldn’t book: {error}', {'error': e});
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
    String clinName(String id) => s.clinicians.where((x) => x.id == id).map((x) => x.short.isEmpty ? x.name : x.short).firstOrNull ?? '';

    final steps = [tr('Patient'), tr('Service'), tr('Date & time'), tr('Confirm')];
    final stepper = LayoutBuilder(
      builder: (context, box) => Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Row(children: [
          for (var i = 0; i < steps.length; i++)
            Expanded(
              child: Semantics(
                selected: i == b.step,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i == b.step ? Portal.navy : Colors.transparent, width: 2))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i == b.step ? Portal.navy : i < b.step ? c.goodSoft : c.surface2),
                      child: i < b.step
                          ? Icon(Icons.check, size: 14, color: c.good)
                          : Text('${i + 1}', style: t.labelMedium?.copyWith(color: i == b.step ? Colors.white : c.muted, fontWeight: FontWeight.w600)),
                    ),
                    if (box.maxWidth > 520) ...[
                      const SizedBox(width: 10),
                      Flexible(child: Text(steps[i], overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: i == b.step ? c.fg : c.muted, fontWeight: i == b.step ? FontWeight.w600 : FontWeight.w500))),
                    ],
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );

    Widget pick({required bool on, required VoidCallback onTap, required Widget child}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: on ? c.accentSoft : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: on ? Portal.navy : c.line, width: on ? 1.5 : 1)),
            child: InkWell(borderRadius: BorderRadius.circular(8), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: child)),
          ),
        );

    Widget body;
    switch (b.step) {
      case 0:
        final q = _find.text.trim().toLowerCase(), qd = q.replaceAll(RegExp(r'\D'), '');
        final known = _known.where((p) => q.isEmpty || p.$1.toLowerCase().contains(q) || (qd.isNotEmpty && p.$2.contains(qd))).take(6).toList();
        final findCol = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Find a patient'), style: t.labelLarge),
          const SizedBox(height: 8),
          TextField(controller: _find, decoration: InputDecoration(hintText: tr('Name or phone number'), prefixIcon: const Icon(Icons.search, size: 20))),
          const SizedBox(height: 12),
          for (final p in known)
            pick(
              on: _digits == p.$2,
              onTap: () {
                _name.text = p.$1;
                _phone.text = _fmtPhone(p.$2);
                b.error = null;
                widget.onChanged();
              },
              child: Row(children: [
                Icon(Icons.person_outline, size: 20, color: c.accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.$1, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                    Text(_fmtPhone(p.$2), style: t.bodySmall),
                  ]),
                ),
              ]),
            ),
          if (known.isEmpty) Text(q.isEmpty ? tr('Patients the front desk booked before show here.') : tr('Nobody matches. Add them as someone new.'), style: t.bodySmall),
        ]);
        final newCol = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Someone new?'), style: t.titleMedium?.copyWith(fontSize: 16)),
          const SizedBox(height: 14),
          TextField(controller: _name, autofocus: true, decoration: InputDecoration(labelText: tr('Full name'))),
          const SizedBox(height: 14),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Mobile number'))),
          const SizedBox(height: 6),
          Text(tr('They’ll get a text to confirm the visit.'), style: t.bodySmall),
        ]);
        body = Columns(children: [findCol, newCol]);
      case 1:
        body = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final x in services)
              pick(
                on: x.id == b.serviceId,
                onTap: () async {
                  if (x.id == b.serviceId) return;
                  await b.release(d);
                  b
                    ..serviceId = x.id
                    ..error = null;
                  widget.onChanged();
                },
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(tr('{n} minutes · {who}', {'n': x.minutes, 'who': x.clinicianIds.map(clinName).where((n) => n.isNotEmpty).join(', ')}), style: t.bodySmall),
                ]),
              ),
            if (services.isEmpty) Text(tr('No service has a clinician yet. Assign clinicians under Services & clinicians.'), style: t.bodySmall?.copyWith(color: c.warn)),
          ]),
        );
      case 2:
        final days = [for (var i = 0; i < 14; i++) isoDate(DateTime.parse(d.today).add(Duration(days: i)))];
        if (!days.contains(b.date)) days.add(b.date);
        final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            key: ValueKey('day${b.date}'),
            initialValue: b.date,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Day')),
            items: [for (final x in days) DropdownMenuItem(value: x, child: Text(longDay(x, d.today, lang: lang)))],
            onChanged: (v) async {
              if (v == null || v == b.date) return;
              await b.release(d);
              b
                ..date = v
                ..error = null;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey('cl${b.clinicianId}${b.serviceId}'),
            initialValue: b.clinicianId,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Clinician')),
            items: [for (final x in clins) DropdownMenuItem(value: x.id, child: Text(x.name))],
            onChanged: (v) => b.pick(d, v!, null, widget.onChanged),
          ),
        ]);
        final right = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Open times'), style: t.labelLarge),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in free)
              SizedBox(
                width: 104,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(96, 44),
                    padding: EdgeInsets.zero,
                    backgroundColor: m == b.minute ? Portal.navy : Colors.white,
                    foregroundColor: m == b.minute ? Colors.white : c.fg,
                    side: BorderSide(color: m == b.minute ? Portal.navy : c.line),
                  ),
                  onPressed: () => b.pick(d, b.clinicianId!, m, widget.onChanged),
                  child: Text(formatTime(m, lang: lang), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          if (cl != null && free.isEmpty) Text(tr('No open times with {clinician} that day. Try another day.', {'clinician': cl.name}), style: t.bodySmall),
          if (free.isNotEmpty) Text(tr('The time is held for you for 2 minutes while you finish.'), style: t.bodySmall),
        ]);
        body = Columns(flex: const [2, 3], children: [left, right]);
      default:
        final rows = [
          (tr('Patient'), '${_name.text.trim()} · ${_fmtPhone(_digits)}'),
          (tr('Service'), svc == null ? '—' : '${svc.name}, ${svc.minutes} min'),
          (tr('With'), cl?.name ?? '—'),
          (tr('When'), b.minute == null ? '—' : '${longDay(b.date, d.today, lang: lang)} · ${formatTime(b.minute!, lang: lang)}'),
        ];
        body = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Check the booking'), style: t.titleMedium),
            const SizedBox(height: 14),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 120, child: Text(k, style: t.bodyMedium?.copyWith(color: c.muted))),
                  Expanded(child: Text(v, style: t.bodyMedium?.copyWith(color: c.fg, fontWeight: k == tr('Patient') ? FontWeight.w600 : null))),
                ]),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.sms_outlined, size: 18, color: c.accent),
              const SizedBox(width: 8),
              Flexible(child: Text(tr('A confirmation text goes to the patient when you book.'), style: t.bodySmall)),
            ]),
          ]),
        );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      stepper,
      const SizedBox(height: 28),
      body,
      const SizedBox(height: 16),
      if (b.minute != null && b.heldUntil != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _HoldCountdown(
            key: ValueKey(b.heldUntil),
            minute: b.minute!,
            until: b.heldUntil!,
            onExpired: () {
              b.minute = null;
              b.error = tr('Your 2-minute hold ran out. Pick the time again.');
              if (b.step == 3) b.step = 2;
              widget.onChanged();
            },
          ),
        ),
      if (b.error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(b.error!, style: t.bodyMedium?.copyWith(color: c.crit, fontWeight: FontWeight.w500))),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.only(top: 16),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
        child: Row(children: [
          b.step == 0 ? OutlinedButton(onPressed: widget.onClose, child: Text(tr('Cancel'))) : OutlinedButton(onPressed: b.busy ? null : _back, child: Text(tr('Back'))),
          const Spacer(),
          FilledButton.icon(
            onPressed: b.busy ? null : _next,
            iconAlignment: IconAlignment.end,
            icon: Icon(b.step == 3 ? Icons.check : Icons.arrow_forward, size: 18),
            label: Text(b.step == 3 ? tr('Book the visit') : tr('Next step')),
          ),
        ]),
      ),
    ]);
  }
}
