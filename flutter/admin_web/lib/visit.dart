import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'ui.dart';

String clinicianShort(ClinicSetup s, String id) {
  final c = s.clinicians.where((c) => c.id == id).firstOrNull;
  return c == null ? tr('Walk-in') : (c.short.isEmpty ? c.name : c.short);
}

String serviceName(ClinicSetup s, String id) => s.services.where((x) => x.id == id).firstOrNull?.name ?? tr('Visit');

/// The clinicians this person sees on the calendar and in the queue: everyone, or just themselves.
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

/// The next step for a visit, as buttons. [primary] marks the one the desk should press next.
List<Widget> visitActions(BuildContext context, ClinicDesk desk, DeskAppt a, {bool primary = false}) {
  // the day's actions happen on the day; other days are booked, moved or cancelled instead
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

/// One visit's details and actions, kept live while open.
Future<void> showVisit(BuildContext context, ClinicSetup setup, ClinicDesk desk, String apptId) => showDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: desk,
        builder: (context, _) {
          final a = desk.appointments.where((x) => x.id == apptId).firstOrNull;
          final t = Theme.of(context).textTheme, c = CfColors.of(context);
          if (a == null) return AlertDialog(content: Text(tr('This visit is no longer available.')));
          Widget line(String label, String value) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 120, child: Text(label, style: t.bodySmall)),
                  Expanded(child: Text(value, style: t.bodyMedium)),
                ]),
              );
          final intake = a.intake;
          return AlertDialog(
            title: Text(a.patientName),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                StatusMark(shownStatus(desk, a), label: tr(shownStatus(desk, a).label)),
                const SizedBox(height: 12),
                line(tr('When'), '${shortDate(a.date, lang: lang)}, ${formatTime(a.minute, lang: lang)}'),
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
                const SizedBox(height: 16),
                RowActions(visitActions(context, desk, a, primary: true)),
                if (!canActOn(desk, a)) Text(tr('Your role can view this visit but not change it.'), style: t.bodySmall?.copyWith(color: c.warn)),
              ]),
            ),
            actions: [
              if (desk.me.runsDay && a.status.upcoming && !desk.clock.passed(a.date, a.minute + 30))
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: c.crit),
                  onPressed: () async {
                    final reason = await _cancelReason(context);
                    if (reason == null || !context.mounted) return;
                    await act(context, () => desk.cancel(a, reason), done: tr('{name}’s visit cancelled. The time is open for the waitlist.', {'name': a.patientName.split(' ').first}));
                  },
                  child: Text(tr('Cancel visit')),
                ),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
            ],
          );
        },
      ),
    );

Future<String?> _cancelReason(BuildContext context) => showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr('Why is the clinic cancelling?')),
        children: [
          for (final r in const ['Clinician is ill', 'Clinic closure', 'Booked in error', 'Patient asked by phone'])
            SimpleDialogOption(onPressed: () => Navigator.pop(context, r), child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(tr(r)))),
          SimpleDialogOption(onPressed: () => Navigator.pop(context), child: Text(tr('Keep the visit'))),
        ],
      ),
    );
