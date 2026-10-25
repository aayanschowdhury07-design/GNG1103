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
    final b = context.backend, c = context.colors, s = context.s, lang = context.lang;
    final late = b.lateCancellation(a.id);
    final cancel = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(header: true, child: Text(s.t('cancelAsk', {'time': formatTime(a.minute, lang: lang)}), style: context.text.headlineSmall)),
            const SizedBox(height: 6),
            Text(
              s.t('cancelWhat', {'service': b.service(a.serviceId).nameIn(lang), 'clinician': b.clinician(a.clinicianId).name, 'day': longDay(a.date, b.today, lang: lang)}),
              style: context.text.bodyMedium,
            ),
            if (late) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(8)),
                child: Text(s.t('lateWarn', {'h': '${b.cancelWindowHours}'}), style: context.text.bodyMedium?.copyWith(color: c.warn, fontWeight: FontWeight.w500)),
              ),
            ],
            const SizedBox(height: 12),
            Text(s.t('cancelNote'), style: context.text.bodySmall),
            const SizedBox(height: 16),
            FilledButton(autofocus: true, onPressed: () => Navigator.pop(context, false), child: Text(s.t('keepVisit'))),
            TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: c.crit), child: Text(s.t('cancelVisit'))),
          ]),
        ),
      ),
    );
    if (cancel == true && context.mounted) {
      await b.cancelVisit(a.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('cancelled'))));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, c = context.colors, s = context.s, lang = context.lang;
      final a = b.myAppointments().firstWhere((x) => x.id == appointmentId);
      void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      final stages = [ApptStatus.booked, ApptStatus.confirmed, ApptStatus.checkedIn, ApptStatus.waiting, ApptStatus.complete];
      final pos = switch (a.status) {
        ApptStatus.booked || ApptStatus.late => 0,
        ApptStatus.confirmed => 1,
        ApptStatus.checkedIn => 2,
        ApptStatus.waiting || ApptStatus.inVisit => 3,
        ApptStatus.complete => 5,
        _ => -1,
      };
      return ScreenFrame(
        title: s.t('visitTitle'),
        children: [
          Row(children: [Expanded(child: Text(longDay(a.date, b.today, lang: lang), style: context.text.bodySmall)), statusMark(context, a.status)]),
          Text('${formatTime(a.minute, lang: lang)} · ${b.service(a.serviceId).short}', style: context.text.titleLarge),
          Text('${b.service(a.serviceId).nameIn(lang)} · ${b.clinician(a.clinicianId).name} · ${b.clinic(a.clinicId).name}, ${b.clinic(a.clinicId).address}', style: context.text.bodySmall),
          Text(s.t('ref', {'id': a.id}), style: context.text.bodySmall),
          Section(
            title: s.t('whereYouAre'),
            child: pos < 0
                ? Text(s.t(a.status == ApptStatus.noShow ? 'visitMissed' : 'visitCancelled'))
                : Column(children: [
                    for (var i = 0; i < stages.length; i++)
                      Semantics(
                        label: i < pos ? s.t('stageDone', {'stage': s.status(stages[i])}) : i == pos ? s.t('stageNow', {'stage': s.status(stages[i])}) : s.status(stages[i]),
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
                            Text(s.status(stages[i]), style: context.text.bodyMedium?.copyWith(color: i < pos ? c.fg : i == pos ? c.accent : c.muted, fontWeight: i == pos ? FontWeight.w600 : null)),
                          ]),
                        ),
                      ),
                  ]),
          ),
          if (a.status.active && !a.formsDone)
            Section(
              title: s.t('beforeArrive'),
              child: Row(children: [
                Expanded(child: Text(s.t('formNow'), style: context.text.bodyMedium)),
                TextButton(onPressed: () => open(IntakeScreen(appointmentId: a.id)), child: Text(s.t('fill'))),
              ]),
            ),
          const SizedBox(height: 16),
          if (a.status == ApptStatus.booked) FilledButton(onPressed: () => b.confirmVisit(a.id), child: Text(s.t('confirmComing'))),
          if ((a.status == ApptStatus.confirmed || a.status == ApptStatus.late) && b.canCheckIn(a))
            FilledButton(onPressed: () => open(CheckInScreen(appointmentId: a.id)), child: Text(s.t('imHere'))),
          if (a.status == ApptStatus.confirmed && !b.canCheckIn(a)) Text(s.t('confirmedWait'), style: context.text.bodyMedium?.copyWith(color: c.good)),
          if (a.status.upcoming) ...[
            TextButton(
              onPressed: () {
                context.draft.startReschedule(b, a);
                open(const BookTimeScreen());
              },
              child: Text(s.t('changeTime')),
            ),
            TextButton(onPressed: () => open(WaitlistScreen(appointmentId: a.id)), child: Text(s.t('getEarlier'))),
            TextButton(onPressed: () => _askCancel(context, a), style: TextButton.styleFrom(foregroundColor: c.crit), child: Text(s.t('cancelVisit'))),
          ],
          const SizedBox(height: 8),
          Text(s.t('cancelPolicy', {'h': '${b.cancelWindowHours}'}), style: context.text.bodySmall),
        ],
      );
    });
  }
}

/// Check-in from the phone, then the ticket the waiting-room screen calls. The phone's
/// location (if the patient shares it) says whether they're at the clinic yet.
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key, required this.appointmentId});
  final String appointmentId;
  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  bool _locating = false, _refused = false;

  Future<void> _locate() async {
    setState(() => _locating = true);
    final ok = await shareLocation(context);
    if (mounted) {
      setState(() {
        _locating = false;
        _refused = !ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, c = context.colors, s = context.s, lang = context.lang;
      final a = b.myAppointments().firstWhere((x) => x.id == widget.appointmentId);
      final clinic = b.clinic(a.clinicId), away = b.distanceKm(clinic);
      if (a.status.upcoming && !b.canCheckIn(a)) {
        return ScreenFrame(
          title: s.t('checkInTitle'),
          children: [
            Text('${longDay(a.date, b.today, lang: lang)} · ${formatTime(a.minute, lang: lang)} · ${b.clinician(a.clinicianId).short}', style: context.text.bodySmall),
            const SizedBox(height: 8),
            Text(s.t('checkInLater'), style: context.text.bodyLarge),
          ],
        );
      }
      if (a.status.upcoming) {
        return ScreenFrame(
          title: s.t('checkInTitle'),
          bottom: FilledButton(onPressed: () => b.checkIn(a.id), child: Text(s.t('imHere'))),
          children: [
            Text('${longDay(a.date, b.today, lang: lang)} · ${formatTime(a.minute, lang: lang)} · ${b.clinician(a.clinicianId).short}', style: context.text.bodySmall),
            const SizedBox(height: 8),
            Text(
              away == null
                  ? s.t('noLocation', {'clinic': clinic.name})
                  : s.t(away <= .2 ? 'nearOpen' : 'farAway', {'d': distanceText(away), 'clinic': clinic.name}),
              style: context.text.bodyLarge,
            ),
            if (away == null)
              Align(
                alignment: Alignment.centerLeft,
                child: _locating
                    ? Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(s.t('locating'), style: context.text.bodySmall))
                    : TextButton.icon(onPressed: _locate, icon: const Icon(Icons.my_location, size: 18), label: Text(s.t('useLocation'))),
              ),
            if (_refused) Text(s.t('locationOff'), style: context.text.bodySmall?.copyWith(color: c.warn)),
            if (!a.formsDone) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(8)),
                child: Text(s.t('formStillOpen'), style: context.text.bodyMedium?.copyWith(color: c.warn)),
              ),
            ],
            if (a.phoneLast4 != null) ...[
              const SizedBox(height: 16),
              Text(s.t('tabletHint', {'d': a.phoneLast4!}), style: context.text.bodySmall),
            ],
          ],
        );
      }
      final ahead = b.peopleAhead(a.id);
      return ScreenFrame(
        title: s.t('checkInTitle'),
        children: [
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Column(children: [
              Text(s.t('checkinTitle'), style: context.text.titleLarge),
              const SizedBox(height: 8),
              Semantics(
                label: a.ticket,
                excludeSemantics: true,
                child: Text(a.ticket ?? '', style: TextStyle(fontSize: 56, fontWeight: FontWeight.w600, height: 1, color: c.stArrived, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              const SizedBox(height: 8),
              Text(s.t('ticketNote'), style: context.text.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                a.status == ApptStatus.checkedIn
                    ? s.t('addingQueue')
                    : ahead == 0
                        ? s.t('youreNext')
                        : s.t('aheadLong', {'n': '$ahead', 'm': '${ahead * 5 + 3}'}),
                style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(s.t('stepOut'), style: context.text.bodySmall),
            ]),
          ),
        ],
      );
    });
  }
}
