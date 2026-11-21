import 'dart:convert';

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'portal_theme.dart';

// ---------------------------------------------------------------- messages

/// A one-line message at the bottom of the screen, with Undo when the change can be reversed.
void say(BuildContext context, String text, {VoidCallback? undo}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: undo == null ? null : SnackBarAction(label: tr('Undo'), onPressed: undo)));
}

/// Runs a change and reports a refused write in plain words instead of failing silently.
Future<void> act(BuildContext context, Future<void> Function() change, {String? done, VoidCallback? undo}) async {
  try {
    await change();
    if (done != null && context.mounted) say(context, done, undo: undo);
  } catch (e) {
    if (context.mounted) say(context, tr('Couldn’t save that: {why}', {'why': '$e'.contains('permission') ? tr('your role can’t make this change') : e}));
  }
}

// ---------------------------------------------------------------- small pieces

enum Tone { good, warn, crit, info, mute }

Color toneColor(CfColors c, Tone t) => switch (t) { Tone.good => c.good, Tone.warn => c.warn, Tone.crit => c.crit, Tone.info => c.accent, Tone.mute => c.muted };
Color toneSoft(CfColors c, Tone t) => switch (t) { Tone.good => c.goodSoft, Tone.warn => c.warnSoft, Tone.crit => c.critSoft, Tone.info => c.accentSoft, Tone.mute => c.surface2 };

/// A short label on a soft background, with a dot.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.tone = Tone.mute});
  final String label;
  final Tone tone;
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), fg = toneColor(c, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: toneSoft(c, tone), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg))),
      ]),
    );
  }
}

/// A section heading with a count and a thin rule, as on the staff website.
class SectionHead extends StatelessWidget {
  const SectionHead(this.title, {super.key, this.count, this.trailing});
  final String title;
  final int? count;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(children: [
        Semantics(header: true, child: Text(title, style: t.titleMedium?.copyWith(fontSize: 16))),
        if (count != null) ...[const SizedBox(width: 8), Text('$count', style: t.bodyMedium?.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]))],
        const Spacer(),
        ?trailing,
      ]),
    );
  }
}

/// A compact button for a row: filled for the one thing to do next, outlined otherwise.
Widget small(String label, VoidCallback? onPressed, {bool primary = false, bool danger = false}) => Builder(builder: (context) {
      final style = ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(44, 40)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
        visualDensity: VisualDensity.compact,
        foregroundColor: danger ? WidgetStatePropertyAll(CfColors.of(context).crit) : null,
      );
      return primary ? FilledButton(style: style, onPressed: onPressed, child: Text(label)) : OutlinedButton(style: style, onPressed: onPressed, child: Text(label));
    });

String initialsOf(String name) => name.replaceFirst(RegExp(r'^Dr\.?\s+'), '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

/// The clinic's uploaded logo (a PNG data URL on the clinic record), or [fallback].
class ClinicLogo extends StatelessWidget {
  const ClinicLogo(this.dataUrl, {super.key, required this.size, required this.fallback});
  final String? dataUrl;
  final double size;
  final Widget fallback;
  @override
  Widget build(BuildContext context) {
    final d = dataUrl ?? '', comma = d.indexOf(',');
    if (!d.startsWith('data:image/') || comma < 0) return fallback;
    try {
      return Image.memory(base64Decode(d.substring(comma + 1)), width: size, height: size, fit: BoxFit.contain, gaplessPlayback: true);
    } catch (_) {
      return fallback;
    }
  }
}

/// The clinic's mark on a navy square: its logo, or the leaf.
class ClinicMark extends StatelessWidget {
  const ClinicMark(this.setup, {super.key, this.size = 34});
  final ClinicSetup setup;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .14),
        decoration: BoxDecoration(color: Portal.navy, borderRadius: BorderRadius.circular(size * .24)),
        child: ClinicLogo(setup.clinic['logo'] as String?, size: size, fallback: Icon(Icons.spa_outlined, size: size * .6, color: Colors.white)),
      );
}

// ---------------------------------------------------------------- visits

String clinicianShort(ClinicSetup s, String id) {
  final c = s.clinicians.where((c) => c.id == id).firstOrNull;
  return c == null ? tr('Walk-in') : (c.short.isEmpty ? c.name : c.short);
}

String serviceName(ClinicSetup s, String id) => s.services.where((x) => x.id == id).firstOrNull?.name ?? tr('Visit');

/// The clinicians this person sees: everyone, or just themselves.
List<SetupClinician> visibleClinicians(ClinicSetup s, ClinicDesk d) =>
    d.me.role == 'clinician' ? s.clinicians.where((c) => c.id == d.me.clinicianId).toList() : s.clinicians;

/// Admins and the front desk act on any visit; a clinician on their own; support on none.
bool canActOn(ClinicDesk d, DeskAppt a) => d.me.runsDay || (d.me.role == 'clinician' && d.me.clinicianId == a.clinicianId);

/// The status to show: a visit past its start without the patient checked in reads Late.
ApptStatus shownStatus(ClinicDesk d, DeskAppt a) => d.isLate(a) ? ApptStatus.late : a.status;

/// Moves a visit along and says what happened, with Undo where it can be reversed.
Future<void> moveVisit(BuildContext context, ClinicDesk desk, DeskAppt a, ApptStatus to) async {
  final first = a.patientName.split(' ').first;
  try {
    final ticket = await desk.setStatus(a, to);
    if (!context.mounted) return;
    final text = switch (to) {
      ApptStatus.checkedIn => tr('{name} checked in · ticket {ticket}', {'name': first, 'ticket': ticket}),
      ApptStatus.waiting => tr('{name} added to the queue', {'name': first}),
      ApptStatus.inVisit => tr('{name} called in', {'name': first}),
      ApptStatus.complete => tr('{name}’s visit complete', {'name': first}),
      ApptStatus.noShow => tr('{name} marked no-show. Listed in Missed visits.', {'name': first}),
      _ => tr('Updated'),
    };
    // checking in hands out a ticket number, so it isn't undone from here
    say(context, text, undo: to == ApptStatus.checkedIn ? null : () => desk.revert(a, to, a.status));
  } catch (e) {
    if (context.mounted) say(context, tr('Couldn’t update {name}’s visit: {why}', {'name': first, 'why': '$e'.contains('permission') ? tr('your role can view this but not change it') : e}));
  }
}

/// The next step for a visit, as buttons. [primary] marks the one to press next.
List<Widget> visitActions(BuildContext context, ClinicDesk desk, DeskAppt a, {bool primary = false}) {
  if (!canActOn(desk, a) || a.date != desk.today) return const [];
  final first = a.patientName.split(' ').first;
  final arrived = small(tr('Arrived'), () => moveVisit(context, desk, a, ApptStatus.checkedIn), primary: primary);
  if (desk.isLate(a)) {
    return [
      arrived,
      if (desk.me.runsDay)
        small(tr('Text'), () => act(context, () => desk.text(a, 'Running late? We’re holding your time for 10 more minutes.'), done: tr('Text to {name} queued', {'name': first}))),
      small(tr('No-show'), () => moveVisit(context, desk, a, ApptStatus.noShow), danger: true),
    ];
  }
  return switch (a.status) {
    ApptStatus.booked || ApptStatus.confirmed => [
        arrived,
        if (a.status == ApptStatus.booked && desk.me.runsDay) small(tr('Remind'), () => act(context, () => desk.remind(a), done: tr('Reminder to {name} queued', {'name': first}))),
        if (!a.formsDone && desk.me.runsDay) small(tr('Send form'), () => act(context, () => desk.sendForm(a), done: tr('Form link to {name} queued', {'name': first}))),
      ],
    ApptStatus.checkedIn => [small(tr('Add to queue'), () => moveVisit(context, desk, a, ApptStatus.waiting), primary: primary)],
    ApptStatus.waiting => [small(tr('Call in'), () => moveVisit(context, desk, a, ApptStatus.inVisit), primary: primary)],
    ApptStatus.inVisit => [small(tr('Complete'), () => moveVisit(context, desk, a, ApptStatus.complete))],
    _ => const [],
  };
}

/// One line about a visit: time, name, a detail line, the status, and its next steps.
class VisitRow extends StatelessWidget {
  const VisitRow({super.key, required this.setup, required this.desk, required this.appt, this.primary = false, this.showActions = true});
  final ClinicSetup setup;
  final ClinicDesk desk;
  final DeskAppt appt;
  final bool primary, showActions;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme, a = appt, st = shownStatus(desk, a);
    final detail = switch (a.status) {
      ApptStatus.waiting => tr('ticket {t} · waiting {n} min', {'t': a.ticket ?? '—', 'n': desk.waited(a)}),
      ApptStatus.inVisit => tr('ticket {t} · in the room', {'t': a.ticket ?? '—'}),
      ApptStatus.checkedIn => tr('ticket {t} · checked in', {'t': a.ticket ?? '—'}),
      _ when desk.isLate(a) => tr('{n} min late · {clinician}', {'n': desk.lateBy(a), 'clinician': clinicianShort(setup, a.clinicianId)}),
      _ => '${serviceName(setup, a.serviceId)} · ${clinicianShort(setup, a.clinicianId)}',
    };
    final actions = showActions ? visitActions(context, desk, a, primary: primary) : const <Widget>[];
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VisitScreen(setup: setup, desk: desk, apptId: a.id))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 74, child: Text(formatTime(a.minute, lang: lang), style: t.bodyMedium?.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.patientName, style: t.bodyLarge?.copyWith(color: c.fg, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(detail, style: t.bodySmall),
              ]),
            ),
            const SizedBox(width: 8),
            StatusMark(st, label: tr(st.label)),
          ]),
          if (actions.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 74, top: 10), child: Wrap(spacing: 8, runSpacing: 8, children: actions)),
        ]),
      ),
    );
  }
}

/// One visit's details and actions, kept live while open.
class VisitScreen extends StatelessWidget {
  const VisitScreen({super.key, required this.setup, required this.desk, required this.apptId});
  final ClinicSetup setup;
  final ClinicDesk desk;
  final String apptId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: desk,
        builder: (context, _) {
          final a = desk.appointments.where((x) => x.id == apptId).firstOrNull;
          final t = Theme.of(context).textTheme, c = CfColors.of(context);
          if (a == null) return Scaffold(appBar: AppBar(), body: Center(child: Text(tr('This visit is no longer available.'))));
          final st = shownStatus(desk, a), intake = a.intake;
          Widget line(String label, String value) => Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 110, child: Text(label, style: t.bodyMedium?.copyWith(color: c.muted))),
                  Expanded(child: Text(value, style: t.bodyMedium?.copyWith(color: c.fg))),
                ]),
              );
          final actions = visitActions(context, desk, a, primary: true);
          return Scaffold(
            appBar: AppBar(title: Text(tr('Visit'))),
            body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
              Text(a.patientName, style: t.headlineSmall),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: StatusMark(st, label: tr(st.label))),
              const SizedBox(height: 12),
              line(tr('When'), '${dayLabel(a.date, desk.today, lang: lang)}, ${formatTime(a.minute, lang: lang)}'),
              line(tr('With'), clinicianShort(setup, a.clinicianId)),
              line(tr('Service'), serviceName(setup, a.serviceId)),
              if (a.ticket != null) line(tr('Ticket'), a.ticket!),
              if (desk.me.runsDay) line(tr('Phone'), a.phone != null && a.phone!.isNotEmpty ? a.phone! : (a.phoneLast4 == null ? tr('Not given') : tr('ends in {last4}', {'last4': a.phoneLast4}))),
              line(tr('Booked'), a.bookedBy != null ? tr('by the front desk') : a.patientUid != null ? tr('online by the patient') : tr('before ClinicFlow')),
              line(tr('Form'), a.formsDone ? tr('Done') : tr('Not filled in yet')),
              if (intake != null) ...[
                line(tr('Visit type'), '${intake['visitType'] ?? ''}'),
                if ('${intake['note'] ?? ''}'.isNotEmpty) line(tr('Note'), '${intake['note']}'),
              ],
              if (a.status == ApptStatus.cancelled) line(tr('Cancelled'), a.cancelledBy == 'clinic' ? tr('by the clinic') : tr('by the patient')),
              const SizedBox(height: 20),
              if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
              if (!canActOn(desk, a)) Text(tr('Your role can view this visit but not change it.'), style: t.bodySmall?.copyWith(color: c.warn)),
              if (desk.me.runsDay && a.status.upcoming && !desk.clock.passed(a.date, a.minute + 30)) ...[
                const SizedBox(height: 24),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: c.crit, alignment: Alignment.centerLeft),
                  icon: const Icon(Icons.event_busy_outlined, size: 20),
                  label: Text(tr('Cancel visit')),
                  onPressed: () async {
                    final reason = await _cancelReason(context);
                    if (reason == null || !context.mounted) return;
                    await act(context, () => desk.cancel(a, reason), done: tr('{name}’s visit cancelled. The time is open for the waitlist.', {'name': a.patientName.split(' ').first}));
                  },
                ),
              ],
            ]),
          );
        },
      );
}

Future<String?> _cancelReason(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(tr('Why is the clinic cancelling?'), style: Theme.of(context).textTheme.titleMedium)),
          for (final r in const ['Clinician is ill', 'Clinic closure', 'Booked in error', 'Patient asked by phone'])
            ListTile(title: Text(tr(r)), onTap: () => Navigator.pop(context, r)),
          ListTile(title: Text(tr('Keep the visit')), onTap: () => Navigator.pop(context)),
        ]),
      ),
    );
