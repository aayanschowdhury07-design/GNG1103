import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

import '../scope.dart';
import '../widgets.dart';
import 'intake.dart';
import 'visit.dart';
import 'waitlist.dart';

/// The visit that matters right now at the patient's own clinic: the next one still ahead,
/// otherwise today's finished one (for the "book your follow-up" nudge).
Appointment? nextHomeVisit(ClinicFlowBackend b) {
  final mine = b.upcomingVisits().where((a) => b.clinic(a.clinicId).isHome).toList();
  return mine.where((a) => a.status.active && a.status != ApptStatus.complete).firstOrNull ?? mine.where((a) => a.date == b.today).lastOrNull;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onBook, required this.onClinics});
  final VoidCallback onBook, onClinics;

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, c = context.colors;
      final next = nextHomeVisit(b);
      final home = b.clinics.where((x) => x.isHome).firstOrNull;
      final elsewhere = b.upcomingVisits().where((a) => !b.clinic(a.clinicId).isHome && a.status.active).toList();
      final offer = b.pendingOffer();
      return ScreenFrame(
        back: false,
        title: 'Good morning, ${context.session.name.split(' ').first}',
        children: [
          _Hero(visit: next, onBook: onBook),
          if (offer != null)
            Material(
              color: c.goodSoft,
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                title: Text('A time opened up: ${dayLabel(offer.date, b.today, midSentence: true)} at ${formatTime(offer.minute)}',
                    style: context.text.bodyMedium?.copyWith(color: c.good, fontWeight: FontWeight.w600)),
                subtitle: Text('Held for you for ${b.offerHoldMinutes} minutes', style: context.text.bodySmall?.copyWith(color: c.good)),
                trailing: Icon(Icons.chevron_right, color: c.good),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OfferScreen())),
              ),
            ),
          if (next != null && next.status.active && next.status != ApptStatus.complete)
            Section(
              title: 'To do before your visit',
              trailing: Text(next.formsDone ? 'All done' : '1 left', style: context.text.labelMedium?.copyWith(color: next.formsDone ? c.good : c.warn)),
              child: Column(children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Contact and consent'),
                  subtitle: Text(b.smsConsent ? 'Text reminders on since ${b.smsConsentChangedOn}' : 'Text reminders off · push and email only'),
                  trailing: Text('Done', style: context.text.labelMedium?.copyWith(color: c.good)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reason for visit'),
                  subtitle: Text(next.formsDone ? 'Submitted' : '2 min · needed before your visit'),
                  trailing: next.formsDone
                      ? Text('Done', style: context.text.labelMedium?.copyWith(color: c.good))
                      : TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IntakeScreen(appointmentId: next.id))), child: const Text('Fill in')),
                ),
              ]),
            ),
          if (elsewhere.isNotEmpty)
            Section(
              title: 'Also booked',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final a in elsewhere)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${dayLabel(a.date, b.today)}, ${formatTime(a.minute)} · ${b.service(a.serviceId).short}'),
                    subtitle: Text('${b.clinician(a.clinicianId).name} · ${b.clinic(a.clinicId).name}, ${b.clinic(a.clinicId).address}'),
                    trailing: StatusMark(a.status),
                  ),
                Text("Booked through the ClinicFlow directory. To change or cancel, use the link in that clinic's confirmation text.", style: context.text.bodySmall),
              ]),
            ),
          Section(
            child: Row(children: [
              Expanded(child: _Tile(title: 'Book a visit', subtitle: '${home == null ? 'At a clinic near you' : 'At ${home.name}'}. No account needed.', onTap: onBook)),
              const SizedBox(width: 24),
              Expanded(
                child: _Tile(
                  title: 'Other clinics',
                  subtitle: '${b.clinics.where((x) => x.accepting && !x.isHome).length} nearby accepting patients',
                  onTap: onClinics,
                ),
              ),
            ]),
          ),
          if (home?.notice != null)
            Section(
              title: 'Notice from ${home!.name}',
              child: Text(home.notice!, style: context.text.bodySmall?.copyWith(color: c.muted)),
            ),
        ],
      );
    });
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.subtitle, required this.onTap});
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: context.text.titleLarge?.copyWith(color: context.colors.accent)),
            Text(subtitle, style: context.text.bodySmall),
          ]),
        ),
      );
}

/// The next visit, with the action that matters most as the filled button:
/// "Confirm I'm coming" until confirmed, then "I'm here".
class _Hero extends StatelessWidget {
  const _Hero({required this.visit, required this.onBook});
  final Appointment? visit;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final b = context.backend, c = context.colors, a = visit;
    final onHero = context.text.bodyMedium?.copyWith(color: c.heroFg);
    final title = context.text.headlineSmall?.copyWith(color: c.heroFg);
    Widget primary(String label, VoidCallback onTap) => FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(backgroundColor: c.heroFg, foregroundColor: c.hero),
          child: Text(label),
        );
    Widget secondary(String label, VoidCallback onTap) => TextButton(onPressed: onTap, style: TextButton.styleFrom(foregroundColor: c.heroFg), child: Text(label));
    void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    final List<Widget> body;
    if (a == null || !a.status.active) {
      body = [Text("Book when you're ready", style: title), Text('No upcoming visit', style: onHero), const SizedBox(height: 12), primary('Book a visit', onBook)];
    } else if (a.status == ApptStatus.checkedIn || a.status == ApptStatus.waiting) {
      final ahead = b.peopleAhead(a.id);
      body = [
        Text('Checked in · ticket ${a.ticket}', style: title),
        Text(a.status == ApptStatus.checkedIn ? 'The front desk is adding you to the queue' : ahead == 0 ? "You're next" : '$ahead ahead of you', style: onHero),
        const SizedBox(height: 12),
        primary('See your place', () => open(CheckInScreen(appointmentId: a.id))),
      ];
    } else if (a.status == ApptStatus.inVisit) {
      body = [Text('${b.clinician(a.clinicianId).short} is ready for you', style: title), Text('Please go to Room 2, down the hall on the left.', style: onHero)];
    } else if (a.status == ApptStatus.complete) {
      body = [Text('Thanks, ${context.session.name.split(' ').first}', style: title), Text('Book your next follow-up while it’s fresh.', style: onHero), const SizedBox(height: 12), primary('Book follow-up', onBook)];
    } else {
      final state = a.status == ApptStatus.confirmed ? 'confirmed' : a.status == ApptStatus.late ? 'you are running late' : 'please confirm';
      body = [
        Text('${formatTime(a.minute)} · ${b.service(a.serviceId).short}', style: title),
        Text('Next visit · ${dayLabel(a.date, b.today, midSentence: true)} · $state', style: onHero?.copyWith(color: c.heroFg.withValues(alpha: .8))),
        Text('${b.clinician(a.clinicianId).name} · ${b.clinic(a.clinicId).name}', style: onHero),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, children: [
          if (a.status == ApptStatus.booked)
            primary("Confirm I'm coming", () => b.confirmVisit(a.id))
          else if (b.canCheckIn(a))
            primary("I'm here", () => open(CheckInScreen(appointmentId: a.id))),
          // before the day, managing the visit is the main thing left to do
          a.status != ApptStatus.booked && !b.canCheckIn(a)
              ? primary('Manage visit', () => open(VisitScreen(appointmentId: a.id)))
              : secondary('Manage visit', () => open(VisitScreen(appointmentId: a.id))),
        ]),
      ];
    }
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body),
    );
  }
}
