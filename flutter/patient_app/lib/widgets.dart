import 'dart:async';

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'scope.dart';
import 'session.dart';

/// Asks for the phone's location (the system asks the patient the first time) and hands it to
/// the backend for distances and check-in. False if location is off or refused.
Future<bool> shareLocation(BuildContext context) async {
  final b = context.backend;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var allowed = await Geolocator.checkPermission();
    if (allowed == LocationPermission.denied) allowed = await Geolocator.requestPermission();
    if (allowed == LocationPermission.denied || allowed == LocationPermission.deniedForever) return false;
    final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
    b.setHere(p.latitude, p.longitude);
    return true;
  } catch (e) {
    debugPrint('location: $e');
    return false;
  }
}

/// "350 m" under a kilometre, "2.4 km" above.
String distanceText(double km) => km < 1 ? '${(km * 1000 / 10).round() * 10} m' : '${km.toStringAsFixed(1)} km';

/// A visit's status mark, in the app's language.
Widget statusMark(BuildContext context, ApptStatus s) => StatusMark(s, label: context.s.status(s));

/// A Canadian or US number as people write it (+1 416 555 0142); anything else as given.
String phoneText(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  final n = d.length == 11 && d.startsWith('1') ? d.substring(1) : d;
  return n.length == 10 ? '+1 ${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6)}' : phone;
}

/// The name to use for the patient themselves: their profile name, or nothing for a visitor.
String myName(BuildContext context) => context.backend.profile?.name ?? '';

/// A section: a hairline rule above and space around. No boxed cards.
class Section extends StatelessWidget {
  const Section({super.key, this.title, required this.child, this.trailing});
  final String? title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.line))),
      padding: const EdgeInsets.only(top: 16),
      margin: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [Expanded(child: Text(title!, style: context.text.titleMedium)), ?trailing]),
          ),
        child,
      ]),
    );
  }
}

/// A screen with a serif title, an optional back button and a scrolling body.
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({super.key, required this.title, required this.children, this.actions, this.bottom, this.back = true});
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? bottom;
  final bool back;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: back,
        title: Semantics(header: true, child: Text(title)),
        actions: actions,
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: children),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              child: Container(
                decoration: BoxDecoration(color: context.colors.bg, border: Border(top: BorderSide(color: context.colors.line))),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: bottom,
              ),
            ),
    );
  }
}

/// Underlined tabs for small either/or choices (filters, language), as in the prototype.
class UnderlineTabs<T> extends StatelessWidget {
  const UnderlineTabs({super.key, required this.options, required this.selected, required this.onSelect, this.label});
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelect;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: label,
      container: true,
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Wrap(spacing: 20, children: [
          for (final (value, text) in options)
            Semantics(
              selected: value == selected,
              button: true,
              child: InkWell(
                onTap: () => onSelect(value),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: value == selected ? c.accent : Colors.transparent, width: 2))),
                  child: Text(text, style: context.text.labelLarge?.copyWith(color: value == selected ? c.fg : c.muted)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// One option in a single-choice list: reads as a radio row, not a box.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({super.key, required this.title, this.subtitle, required this.selected, required this.onTap, this.leading});
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: selected ? c.accent : c.fg)),
                if (subtitle != null) Text(subtitle!, style: context.text.bodySmall),
              ]),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 20,
              height: 20,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? c.accent : c.lineStrong, width: selected ? 6 : 1.5)),
            ),
          ]),
        ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CircleAvatar(radius: 17, backgroundColor: context.colors.surface2, child: Text(text, style: context.text.labelMedium?.copyWith(color: context.colors.fg))),
      );
}

String initials(String name) => name.replaceAll('Dr. ', '').replaceAll(',', '').split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase();

class ErrorLine extends StatelessWidget {
  const ErrorLine(this.message, {super.key});
  final String? message;
  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message!, style: context.text.bodyMedium?.copyWith(color: context.colors.crit, fontWeight: FontWeight.w500)),
          ),
        );
}

/// "2:30 pm with Dr. Osei is held for you for 4:58". Only this line redraws every second,
/// so typing elsewhere on the screen is never disturbed. Calls [onExpired] once when the hold runs out.
class HoldBar extends StatefulWidget {
  const HoldBar({super.key, this.onExpired});
  final VoidCallback? onExpired;
  @override
  State<HoldBar> createState() => _HoldBarState();
}

class _HoldBarState extends State<HoldBar> {
  Timer? _timer;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final hold = context.backend.holdOf(BookingDraft.owner);
      // only the screen on top reacts, so a screen left behind in the stack can't navigate
      final onTop = ModalRoute.of(context)?.isCurrent ?? true;
      if (hold == null && context.draft.minute != null && onTop && !_fired) {
        _fired = true;
        widget.onExpired?.call();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hold = context.backend.holdOf(BookingDraft.owner);
    if (hold == null) return const SizedBox.shrink();
    final left = hold.left, c = context.colors;
    final mmss = '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(Icons.lock_outline, size: 16, color: c.warn),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            context.s.t('held', {
              'time': '${dayLabel(hold.date, context.backend.today, lang: context.lang)}, ${formatTime(hold.minute, lang: context.lang)}',
              'who': context.backend.clinician(hold.clinicianId).short,
              'left': mmss,
            }),
            style: context.text.bodySmall?.copyWith(color: c.warn, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      ]),
    );
  }
}

/// English / Français switch for the booking flow.
class LangSwitch extends StatelessWidget {
  const LangSwitch({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: UnderlineTabs<String>(
          label: 'Language / Langue',
          options: const [('en', 'EN'), ('fr', 'FR')],
          selected: context.lang,
          onSelect: context.session.setLang,
        ),
      );
}

/// Booking summary: service, who it's for, clinician, time and clinic.
class BookingSummary extends StatelessWidget {
  const BookingSummary({super.key, required this.serviceId, required this.clinicianId, required this.date, required this.minute, required this.clinicId, required this.who});
  final String serviceId, clinicianId, date, clinicId, who;
  final int? minute;

  @override
  Widget build(BuildContext context) {
    final b = context.backend, cl = b.clinic(clinicId);
    // '' is the patient themselves
    final forWhom = who.isNotEmpty ? who : myName(context);
    final lines = [
      forWhom.isEmpty ? context.s.t('forYou') : context.s.t('forWho', {'name': forWhom}),
      b.clinician(clinicianId).name,
      '${longDay(date, b.today, lang: context.lang)}${minute == null ? '' : ' · ${formatTime(minute!, lang: context.lang)}'}',
      '${cl.name}, ${cl.address}',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(b.service(serviceId).nameIn(context.lang), style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      for (final l in lines) Text(l, style: context.text.bodyMedium),
    ]);
  }
}
