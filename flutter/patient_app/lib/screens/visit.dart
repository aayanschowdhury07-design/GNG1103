import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

import '../scope.dart';
import '../widgets.dart';
import 'booking.dart';
import 'intake.dart';
import 'waitlist.dart';

/// One visit: status, where it is in the day, and what the patient can do next.
class VisitScreen extends StatelessWidget {
  const VisitScreen({super.key, required this.appointmentId});
  final String appointmentId;

  /// Cancelling can't be undone, so it asks first, with "Keep my visit" as the default.
  Future<void> _askCancel(BuildContext context, Appointment a) async {
    final b = context.backend, c = context.colors;
    final late = b.lateCancellation(a.id);
    final cancel = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(header: true, child: Text('Cancel your ${formatTime(a.minute)} visit?', style: context.text.headlineSmall)),
            const SizedBox(height: 6),
            Text('${b.service(a.serviceId).name} with ${b.clinician(a.clinicianId).name}, ${longDay(a.date, b.today)}.', style: context.text.bodyMedium),
            if (late) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(8)),
                child: Text('Your visit is less than ${b.cancelWindowHours} hours away, so the clinic may record a late cancellation.',
                    style: context.text.bodyMedium?.copyWith(color: c.warn, fontWeight: FontWeight.w500)),
              ),
            ],
            const SizedBox(height: 12),
            Text('Your time goes to the next person on the waitlist. You can book again any time.', style: context.text.bodySmall),
            const SizedBox(height: 16),
            FilledButton(autofocus: true, onPressed: () => Navigator.pop(context, false), child: const Text('Keep my visit')),
            TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: c.crit), child: const Text('Cancel visit')),
          ]),
        ),
      ),
    );
    if (cancel == true && context.mounted) {
      await b.cancelVisit(a.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visit cancelled. Your time is offered to the waitlist.')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, c = context.colors;
      final a = b.myAppointments().firstWhere((x) => x.id == appointmentId);
      void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      const stages =['Booked', 'Confirmed', 'Checked in', 'Waiting', 'Complete'];
      final pos = switch (a.status) {
        ApptStatus.booked || ApptStatus.late => 0,
        ApptStatus.confirmed => 1,
        ApptStatus.checkedIn => 2,
        ApptStatus.waiting || ApptStatus.inVisit => 3,
        ApptStatus.complete => 5,
        _ => -1,
      };
      return ScreenFrame(
        title: 'Your visit',
        children: [
          Row(children: [Expanded(child: Text(longDay(a.date, b.today), style: context.text.bodySmall)), StatusMark(a.status)]),
          Text('${formatTime(a.minute)} · ${b.service(a.serviceId).short}', style: context.text.titleLarge),
          Text('${b.service(a.serviceId).name} · ${b.clinician(a.clinicianId).name} · ${b.clinic(a.clinicId).name}, ${b.clinic(a.clinicId).address}', style: context.text.bodySmall),
          Text('Ref ${a.id}', style: context.text.bodySmall),
          Section(
            title: 'Where you are',
            child: pos < 0
                ? Text('This visit was ${a.status == ApptStatus.noShow ? 'missed' : 'cancelled'}.')
                : Column(children: [
                    for (var i = 0; i < stages.length; i++)
                      Semantics(
                        label: '${stages[i]}${i < pos ? ', done' : i == pos ? ', current step' : ''}',
                        excludeSemantics: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < pos ? c.good : null,
                                border: Border.all(color: i < pos ? c.good : i == pos ? c.accent : c.muted, width: 1.5),
                              ),
                              child: i < pos ? Icon(Icons.check, size: 14, color: c.bg) : Text('${i + 1}', style: context.text.labelMedium?.copyWith(color: i == pos ? c.accent : c.muted)),
                            ),
                            const SizedBox(width: 12),
                            Text(stages[i], style: context.text.bodyMedium?.copyWith(color: i < pos ? c.fg : i == pos ? c.accent : c.muted, fontWeight: i == pos ? FontWeight.w600 : null)),
                          ]),
                        ),
                      ),
                  ]),
          ),
          if (a.status.active && !a.formsDone && b.clinic(a.clinicId).isHome)
            Section(
              title: 'Before you arrive',
              child: Row(children: [
                Expanded(child: Text('Reason-for-visit form · 2 minutes', style: context.text.bodyMedium)),
                TextButton(onPressed: () => open(IntakeScreen(appointmentId: a.id)), child: const Text('Fill in')),
              ]),
            ),
          const SizedBox(height: 16),
          if (a.status == ApptStatus.booked) FilledButton(onPressed: () => b.confirmVisit(a.id), child: const Text("Confirm I'm coming")),
          if ((a.status == ApptStatus.confirmed || a.status == ApptStatus.late) && b.canCheckIn(a))
            FilledButton(onPressed: () => open(CheckInScreen(appointmentId: a.id)), child: const Text("I'm here")),
          if (a.status == ApptStatus.confirmed && !b.canCheckIn(a))
            Text('Confirmed. Check-in opens on the day of your visit.', style: context.text.bodyMedium?.copyWith(color: c.good)),
          if (a.status.upcoming && b.clinic(a.clinicId).isHome) ...[
            TextButton(
              onPressed: () {
                context.draft.startReschedule(b, a);
                open(const BookTimeScreen());
              },
              child: const Text('Change the time'),
            ),
            TextButton(onPressed: () => open(const WaitlistScreen()), child: const Text('Get offered an earlier time')),
          ],
          if (a.status.upcoming)
            TextButton(onPressed: () => _askCancel(context, a), style: TextButton.styleFrom(foregroundColor: c.crit), child: const Text('Cancel visit')),
          const SizedBox(height: 8),
          Text('Free cancellation until ${b.cancelWindowHours} hours before your visit. After that the clinic may record a late cancellation.', style: context.text.bodySmall),
        ],
      );
    });
  }
}

/// Check-in from the phone, then the ticket the waiting-room screen calls.
class CheckInScreen extends StatelessWidget {
  const CheckInScreen({super.key, required this.appointmentId});
  final String appointmentId;

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, c = context.colors, s = context.s;
      final a = b.myAppointments().firstWhere((x) => x.id == appointmentId);
      if (a.status.upcoming && !b.canCheckIn(a)) {
        return ScreenFrame(
          title: 'Check in',
          children: [
            Text('${longDay(a.date, b.today)} · ${formatTime(a.minute)} · ${b.clinician(a.clinicianId).short}', style: context.text.bodySmall),
            const SizedBox(height: 8),
            Text('Check-in opens on the day of your visit, from 1 hour before.', style: context.text.bodyLarge),
          ],
        );
      }
      if (a.status.upcoming) {
        return ScreenFrame(
          title: 'Check in',
          bottom: FilledButton(onPressed: () => b.checkIn(a.id), child: const Text("I'm here")),
          children: [
            Text('Today · ${formatTime(a.minute)} · ${b.clinician(a.clinicianId).short}', style: context.text.bodySmall),
            const SizedBox(height: 8),
            Text("You're 140 m from ${b.clinic(a.clinicId).name}. Check-in is open.", style: context.text.bodyLarge),
            if (!a.formsDone && b.clinic(a.clinicId).isHome) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(8)),
                child: Text('One form is still open. You can check in now and finish it while you wait.', style: context.text.bodyMedium?.copyWith(color: c.warn)),
              ),
            ],
            const SizedBox(height: 16),
            Text('No phone signal? On the front-desk tablet, enter the last 4 digits of your phone: ${a.phoneLast4 ?? '0142'}', style: context.text.bodySmall),
          ],
        );
      }
      final ahead = b.peopleAhead(a.id);
      return ScreenFrame(
        title: 'Check in',
        children: [
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Column(children: [
              Text(s.t('checkinTitle'), style: context.text.titleLarge),
              const SizedBox(height: 8),
              Semantics(label: 'Ticket ${a.ticket}', excludeSemantics: true, child: Text(a.ticket ?? '', style: TextStyle(fontSize: 56, fontWeight: FontWeight.w600, height: 1, color: c.stArrived, fontFeatures: const [FontFeature.tabularFigures()]))),
              const SizedBox(height: 8),
              Text(s.t('ticketNote'), style: context.text.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                a.status == ApptStatus.checkedIn ? 'The front desk is adding you to the queue' : ahead == 0 ? "You're next" : '$ahead ${ahead == 1 ? 'person' : 'people'} ahead of you · about ${ahead * 5 + 3} min',
                style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text("Feel free to step out; we'll send a push when you're next.", style: context.text.bodySmall),
            ]),
          ),
        ],
      );
    });
  }
}
