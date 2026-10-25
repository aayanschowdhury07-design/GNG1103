import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

import '../scope.dart';
import '../widgets.dart';
import 'home.dart';
import 'intake.dart';
import 'waitlist.dart';

/// Every message the clinic sent, newest first. Each says what kind it is in words,
/// and the ones that ask for something carry the button to do it.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, c = context.colors, s = context.s, next = nextVisit(b);
      Color kindColor(NoticeKind k) => switch (k) {
            NoticeKind.todo => c.warn,
            NoticeKind.offer => c.good,
            NoticeKind.reminder => c.accent,
            _ => c.muted,
          };
      List<Widget> actions(PatientNotice n) {
        void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
        return switch (n.action) {
          NoticeAction.confirm when next != null && next.status == ApptStatus.booked => [FilledButton(onPressed: () => b.confirmVisit(next.id), child: Text(s.t('confirm')))],
          NoticeAction.intake when next != null && !next.formsDone => [TextButton(onPressed: () => open(IntakeScreen(appointmentId: next.id)), child: Text(s.t('fillForm')))],
          NoticeAction.offer when b.pendingOffer() != null => [FilledButton(onPressed: () => open(const OfferScreen()), child: Text(s.t('seeOffer')))],
          _ => const [],
        };
      }

      final notices = b.notifications();
      return ScreenFrame(
        back: false,
        title: s.t('notifTitle'),
        children: [
          if (notices.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(s.t('noNotifs'), style: context.text.bodyMedium?.copyWith(color: c.muted))),
          for (final n in notices)
            Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.text, style: context.text.bodyMedium),
                const SizedBox(height: 2),
                Text.rich(TextSpan(style: context.text.bodySmall, children: [
                  TextSpan(text: s.kind(n.kind), style: TextStyle(color: kindColor(n.kind), fontWeight: FontWeight.w600)),
                  TextSpan(text: ' · ${n.when}'),
                ])),
                if (actions(n).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 8, children: actions(n))),
              ]),
            ),
        ],
      );
    });
  }
}
