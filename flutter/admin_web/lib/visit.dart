import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'ui.dart';

String clinicianShort(ClinicSetup s, String id) {
  final c = s.clinicians.where((c) => c.id == id).firstOrNull;
  return c == null ? 'Walk-in' : (c.short.isEmpty ? c.name : c.short);
}

String serviceName(ClinicSetup s, String id) => s.services.where((x) => x.id == id).firstOrNull?.name ?? 'Visit';

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
      ApptStatus.checkedIn => '$first checked in · ticket $ticket',
      ApptStatus.waiting => '$first added to the queue',
      ApptStatus.inVisit => '$first called in',
      ApptStatus.complete => '$first’s visit complete',
      ApptStatus.noShow => '$first marked no-show. Listed in Missed visits.',
      _ => 'Updated',
    };
    // checking in hands out a ticket number, so it isn't undone from here
    say(context, text, undo: to == ApptStatus.checkedIn ? null : () => desk.revert(a, to, a.status));
  } catch (e) {
    if (context.mounted) say(context, 'Couldn’t update $first’s visit: ${'$e'.contains('permission') ? 'your role can view this but not change it' : e}');
  }
}

/// The next step for a visit, as buttons. [primary] marks the one the desk should press next.
List<Widget> visitActions(BuildContext context, ClinicDesk desk, DeskAppt a, {bool primary = false}) {
  // the day's actions happen on the day; other days are booked, moved or cancelled instead
  if (!canActOn(desk, a) || a.date != desk.today) return const [];
  final first = a.patientName.split(' ').first;
  final arrived = small('Arrived', () => moveVisit(context, desk, a, ApptStatus.checkedIn), primary: primary);
  if (desk.isLate(a)) {
    return [
      arrived,
      if (desk.me.runsDay)
        small('Text', () => act(context, () => desk.text(a, 'Running late? We’re holding your time for 10 more minutes.'), done: 'Text to $first queued')),
      small('No-show', () => moveVisit(context, desk, a, ApptStatus.noShow), danger: true),
    ];
  }
  return switch (a.status) {
    ApptStatus.booked || ApptStatus.confirmed => [
        arrived,
        if (a.status == ApptStatus.booked && desk.me.runsDay) small('Remind', () => act(context, () => desk.remind(a), done: 'Reminder to $first queued')),
        if (!a.formsDone && desk.me.runsDay) small('Send form', () => act(context, () => desk.sendForm(a), done: 'Form link to $first queued')),
      ],
    ApptStatus.checkedIn => [small('Add to queue', () => moveVisit(context, desk, a, ApptStatus.waiting), primary: primary)],
    ApptStatus.waiting => [small('Call in', () => moveVisit(context, desk, a, ApptStatus.inVisit), primary: primary)],
    ApptStatus.inVisit => [small('Complete', () => moveVisit(context, desk, a, ApptStatus.complete))],
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
          if (a == null) return const AlertDialog(content: Text('This visit is no longer available.'));
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
                StatusMark(shownStatus(desk, a)),
                const SizedBox(height: 12),
                line('When', '${shortDate(a.date)}, ${formatTime(a.minute)}'),
                line('With', clinicianShort(setup, a.clinicianId)),
                line('Service', serviceName(setup, a.serviceId)),
                if (a.ticket != null) line('Ticket', a.ticket!),
                if (desk.me.runsDay) line('Phone', a.phone != null && a.phone!.isNotEmpty ? a.phone! : (a.phoneLast4 == null ? 'Not given' : 'ends in ${a.phoneLast4}')),
                line('Booked', a.bookedBy != null ? 'by the front desk' : a.patientUid != null ? 'online by the patient' : 'before ClinicFlow'),
                line('Form', a.formsDone ? 'Done' : 'Not filled in yet'),
                if (intake != null) ...[
                  line('Visit type', '${intake['visitType'] ?? ''}'),
                  if ('${intake['note'] ?? ''}'.isNotEmpty) line('Note', '${intake['note']}'),
                ],
                if (a.status == ApptStatus.cancelled) line('Cancelled', a.cancelledBy == 'clinic' ? 'by the clinic' : 'by the patient'),
                const SizedBox(height: 16),
                RowActions(visitActions(context, desk, a, primary: true)),
                if (!canActOn(desk, a)) Text('Your role can view this visit but not change it.', style: t.bodySmall?.copyWith(color: c.warn)),
              ]),
            ),
            actions: [
              if (desk.me.runsDay && a.status.upcoming && !desk.clock.passed(a.date, a.minute + 30))
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: c.crit),
                  onPressed: () async {
                    final reason = await _cancelReason(context);
                    if (reason == null || !context.mounted) return;
                    await act(context, () => desk.cancel(a, reason), done: '${a.patientName.split(' ').first}’s visit cancelled. The time is open for the waitlist.');
                  },
                  child: const Text('Cancel visit'),
                ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          );
        },
      ),
    );

Future<String?> _cancelReason(BuildContext context) => showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Why is the clinic cancelling?'),
        children: [
          for (final r in const ['Clinician is ill', 'Clinic closure', 'Booked in error', 'Patient asked by phone'])
            SimpleDialogOption(onPressed: () => Navigator.pop(context, r), child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(r))),
          SimpleDialogOption(onPressed: () => Navigator.pop(context), child: const Text('Keep the visit')),
        ],
      ),
    );
