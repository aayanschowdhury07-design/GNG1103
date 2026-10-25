import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

import '../scope.dart';
import '../widgets.dart';
import 'intake.dart';
import 'visit.dart';
import 'waitlist.dart';

/// The visit that matters right now: the next one still ahead (at the patient's own clinic
/// first), otherwise today's finished one (for the "book your follow-up" nudge).
Appointment? nextVisit(ClinicFlowBackend b) {
  final ahead = b.upcomingVisits().where((a) => a.status.active && a.status != ApptStatus.complete).toList();
  return ahead.where((a) => b.clinic(a.clinicId).isHome).firstOrNull ??
      ahead.firstOrNull ??
      b.upcomingVisits().where((a) => a.date == b.today && a.status == ApptStatus.complete).lastOrNull;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onBook, required this.onClinics});
  final VoidCallback onBook, onClinics;

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, c = context.colors, s = context.s, lang = context.lang;
      final next = nextVisit(b);
      final home = b.clinics.where((x) => x.isHome).firstOrNull;
      final elsewhere = b.upcomingVisits().where((a) => a != next && a.status.active).toList();
      final offer = b.pendingOffer();
      final hour = b.clock.now().hour, first = b.profile?.firstName ?? '';
      final greeting = s.t(hour < 12 ? 'greetMorning' : hour < 17 ? 'greetAfternoon' : 'greetEvening');
      return ScreenFrame(
        back: false,
        title: first.isEmpty ? greeting : '$greeting, $first',
        children: [
          _Hero(visit: next, onBook: onBook),
          if (offer != null)
            Material(
              color: c.goodSoft,
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                title: Text(s.t('offerBanner', {'when': '${dayLabel(offer.date, b.today, lang: lang, midSentence: true)}, ${formatTime(offer.minute, lang: lang)}'}),
                    style: context.text.bodyMedium?.copyWith(color: c.good, fontWeight: FontWeight.w600)),
                subtitle: Text(s.t('heldFor', {'min': '${b.offerHoldMinutes}'}), style: context.text.bodySmall?.copyWith(color: c.good)),
                trailing: Icon(Icons.chevron_right, color: c.good),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OfferScreen())),
              ),
            ),
          if (next != null && next.status.active && next.status != ApptStatus.complete)
            Section(
              title: s.t('todoTitle'),
              trailing: Text(s.t(next.formsDone ? 'allDone' : 'oneLeft'), style: context.text.labelMedium?.copyWith(color: next.formsDone ? c.good : c.warn)),
              child: Column(children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('consentTitle')),
                  subtitle: Text(b.smsConsent ? s.t('smsOnSince', {'date': recordDate(b.smsConsentChangedOn, lang: context.lang)}) : s.t('smsOffShort')),
                  trailing: Text(s.t('doneShort'), style: context.text.labelMedium?.copyWith(color: c.good)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('reasonTitle')),
                  subtitle: Text(s.t(next.formsDone ? 'submitted' : 'formNeeded')),
                  trailing: next.formsDone
                      ? Text(s.t('doneShort'), style: context.text.labelMedium?.copyWith(color: c.good))
                      : TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IntakeScreen(appointmentId: next.id))), child: Text(s.t('fill'))),
                ),
              ]),
            ),
          if (elsewhere.isNotEmpty)
            Section(
              title: s.t('alsoBooked'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final a in elsewhere)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${dayLabel(a.date, b.today, lang: lang)}, ${formatTime(a.minute, lang: lang)} · ${b.service(a.serviceId).short}'),
                    subtitle: Text('${b.clinician(a.clinicianId).name} · ${b.clinic(a.clinicId).name}, ${b.clinic(a.clinicId).address}'),
                    trailing: statusMark(context, a.status),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VisitScreen(appointmentId: a.id))),
                  ),
              ]),
            ),
          Section(
            child: Row(children: [
              Expanded(child: _Tile(title: s.t('tileBook'), subtitle: home == null ? s.t('tileBookNear') : s.t('tileBookAt', {'clinic': home.name}), onTap: onBook)),
              const SizedBox(width: 24),
              Expanded(
                child: _Tile(
                  title: s.t('tileOther'),
                  subtitle: s.t('tileOtherSub', {'n': '${b.clinics.where((x) => x.accepting && !x.isHome).length}'}),
                  onTap: onClinics,
                ),
              ),
            ]),
          ),
          // the notice from the clinic of the next visit (or the patient's own clinic)
          for (final cl in {if (next != null) b.clinic(next.clinicId), ?home})
            if (cl.notice != null && cl.notice!.isNotEmpty)
              Section(
                title: s.t('noticeFrom', {'clinic': cl.name}),
                child: Text(cl.notice!, style: context.text.bodySmall?.copyWith(color: c.muted)),
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
/// "Confirm I'm coming" until confirmed, then "I'm here" on the day.
class _Hero extends StatelessWidget {
  const _Hero({required this.visit, required this.onBook});
  final Appointment? visit;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final b = context.backend, c = context.colors, a = visit, s = context.s, lang = context.lang;
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
      body = [Text(s.t('heroNone'), style: title), Text(s.t('heroNoneSub'), style: onHero), const SizedBox(height: 12), primary(s.t('tileBook'), onBook)];
    } else if (a.status == ApptStatus.checkedIn || a.status == ApptStatus.waiting) {
      final ahead = b.peopleAhead(a.id);
      body = [
        Text(s.t('heroChecked', {'ticket': a.ticket ?? ''}), style: title),
        Text(a.status == ApptStatus.checkedIn ? s.t('addingQueue') : ahead == 0 ? s.t('youreNext') : s.t('aheadShort', {'n': '$ahead'}), style: onHero),
        const SizedBox(height: 12),
        primary(s.t('seePlace'), () => open(CheckInScreen(appointmentId: a.id))),
      ];
    } else if (a.status == ApptStatus.inVisit) {
      body = [Text(s.t('heroReady', {'who': b.clinician(a.clinicianId).short}), style: title), Text(s.t('heroReadySub'), style: onHero)];
    } else if (a.status == ApptStatus.complete) {
      body = [Text(s.t('heroThanks'), style: title), Text(s.t('heroThanksSub'), style: onHero), const SizedBox(height: 12), primary(s.t('bookFollowUp'), onBook)];
    } else {
      final state = s.t(a.status == ApptStatus.confirmed ? 'stConfirmed' : a.status == ApptStatus.late ? 'stLate' : 'stPlease');
      body = [
        Text('${formatTime(a.minute, lang: lang)} · ${b.service(a.serviceId).short}', style: title),
        Text(s.t('heroNext', {'day': dayLabel(a.date, b.today, lang: lang, midSentence: true), 'state': state}), style: onHero?.copyWith(color: c.heroFg.withValues(alpha: .8))),
        Text('${b.clinician(a.clinicianId).name} · ${b.clinic(a.clinicId).name}', style: onHero),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, children: [
          if (a.status == ApptStatus.booked)
            primary(s.t('confirmComing'), () => b.confirmVisit(a.id))
          else if (b.canCheckIn(a))
            primary(s.t('imHere'), () => open(CheckInScreen(appointmentId: a.id))),
          // before the day, managing the visit is the main thing left to do
          a.status != ApptStatus.booked && !b.canCheckIn(a)
              ? primary(s.t('manageVisit'), () => open(VisitScreen(appointmentId: a.id)))
              : secondary(s.t('manageVisit'), () => open(VisitScreen(appointmentId: a.id))),
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
