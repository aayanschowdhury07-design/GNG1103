import 'dart:math';

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_patient/main.dart';
import 'package:clinicflow_patient/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home leads with confirming the next visit, then confirms it', (tester) async {
    final backend = DemoBackend(random: Random(1));
    await tester.pumpWidget(PatientApp(backend: backend, session: PatientSession()));
    await tester.pump();

    expect(find.text('Good morning, Priya'), findsOneWidget);
    expect(find.text('9:00 am · Physio follow-up'), findsOneWidget);
    await tester.tap(find.text("Confirm I'm coming"));
    await tester.pump();

    expect(backend.myAppointments().first.status, ApptStatus.confirmed);
    expect(find.text("I'm here"), findsOneWidget);

    // stop the sample backend's hold-expiry timer before the test ends
    backend.dispose();
  });

  testWidgets('a full booking ends on the confirmation screen and stays there', (tester) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = DemoBackend(random: Random(1));
    await tester.pumpWidget(PatientApp(backend: backend, session: PatientSession()));
    await tester.pump();

    await tester.tap(find.text('Book').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3:30 pm'));
    await tester.pump();
    expect(find.textContaining('is held for you'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('I agree to the 24-hour cancellation policy.'));
    await tester.pump();
    await tester.tap(find.text('Send verification code'));
    await tester.pumpAndSettle();
    final code = RegExp(r'\d{6}').firstMatch(backend.inbox.value!)!.group(0)!;
    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();

    expect(find.text("You're booked"), findsWidgets);
    // the spent hold must not send the patient back to choose a time
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text("You're booked"), findsWidgets);
    expect(find.textContaining('ran out'), findsNothing);
    expect(backend.slotState('osei', backend.today, 930), SlotState.taken);

    await tester.pumpWidget(const SizedBox());
    backend.dispose();
  });

  Future<DemoBackend> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = DemoBackend(random: Random(1));
    await tester.pumpWidget(PatientApp(backend: backend, session: PatientSession()));
    await tester.pump();
    return backend;
  }

  Future<void> close(WidgetTester tester, DemoBackend backend) async {
    await tester.pumpWidget(const SizedBox());
    backend.dispose();
  }

  testWidgets('the reason-for-visit form from Home marks the to-do done', (tester) async {
    final backend = await openApp(tester);
    expect(find.text('1 left'), findsOneWidget);
    await tester.tap(find.text('Fill in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ground-floor room, please.');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('All done'), findsOneWidget);
    expect(backend.myAppointments().first.formsDone, isTrue);
    await close(tester, backend);
  });

  testWidgets('change the time moves the visit without asking for details again', (tester) async {
    final backend = await openApp(tester);
    await tester.tap(find.text('Manage visit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change the time'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a new time'), findsOneWidget);
    await tester.tap(find.text('4:00 pm'));
    await tester.pump();
    await tester.tap(find.text('Move my visit'));
    await tester.pumpAndSettle();
    expect(find.text('Moved to Today, 4:00 pm'), findsOneWidget);
    expect(backend.myAppointments().first.minute, 960);
    await close(tester, backend);
  });

  testWidgets('a visit can be moved to another day, and check-in waits for that day', (tester) async {
    final backend = await openApp(tester);
    final later = backend.bookableDays.skip(1).firstWhere((d) => backend.workingOn('osei', d));
    await tester.tap(find.text('Manage visit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change the time'));
    await tester.pumpAndSettle();
    // the day strip: pick the first later day Dr. Osei works, then 10:00 am on it
    await tester.tap(find.bySemanticsLabel(RegExp('^${RegExp.escape(longDay(later, backend.today))}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10:00 am'));
    await tester.pump();
    await tester.tap(find.text('Move my visit'));
    await tester.pumpAndSettle();
    final a = backend.myAppointments().first;
    expect((a.date, a.minute), (later, 600));
    // back on the visit: its new day, and no check-in until then
    expect(find.text(longDay(later, backend.today)), findsOneWidget);
    expect(find.text("I'm here"), findsNothing);
    await tester.tap(find.text("Confirm I'm coming"));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed. Check-in opens on the day of your visit.'), findsOneWidget);
    await close(tester, backend);
  });

  testWidgets('joining the waitlist leads to an offer the patient can take', (tester) async {
    final backend = await openApp(tester);
    await tester.tap(find.text('Manage visit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get offered an earlier time'));
    await tester.pumpAndSettle();
    // weekdays are picked already; on a weekend, add today
    final today = weekdayOf(backend.today);
    if (today == 'Sat' || today == 'Sun') await tester.tap(find.text(today));
    await tester.tap(find.text('Join waitlist'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3)); // the sample day's 10:30 slot frees up
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(Scaffold).last)).popUntil((r) => r.isFirst);
    await tester.pumpAndSettle();
    await tester.tap(find.text('A time opened up: today, 10:30 am'));
    await tester.pumpAndSettle();
    expect(find.text('An earlier time opened'), findsNothing); // 10:30 is later than 9:00
    await tester.tap(find.text('Take this time'));
    await tester.pumpAndSettle();
    expect(backend.myAppointments().first.minute, 630);
    await tester.pump(const Duration(seconds: 7)); // let the demo text banner time out
    await close(tester, backend);
  });

  testWidgets('signing out shows sign-in; a code from Messages signs back in', (tester) async {
    final backend = await openApp(tester);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Send me a code'), findsOneWidget);
    await tester.tap(find.text('Send me a code'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('From Messages'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(backend.signedIn, isTrue);
    expect(find.text('Sign out'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await close(tester, backend);
  });

  testWidgets('adding a family member while booking books the visit for them', (tester) async {
    final backend = await openApp(tester);
    await tester.tap(find.text('Book').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Leela Raman');
    await tester.tap(find.textContaining("I'm their parent or guardian"));
    await tester.tap(find.text('Add family member'));
    await tester.pumpAndSettle();
    expect(backend.family().map((f) => f.name), contains('Leela Raman'));
    expect(find.text('Leela'), findsOneWidget); // now a choice under "Who is this visit for?"
    await close(tester, backend);
  });

  testWidgets('the patient edits their name and email on Profile', (tester) async {
    final backend = await openApp(tester);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Priya Raman'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Priya R. Raman');
    await tester.enterText(find.byType(TextField).last, 'priya@example.org');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((backend.profile!.name, backend.profile!.email), ('Priya R. Raman', 'priya@example.org'));
    expect(find.text('Priya R. Raman'), findsOneWidget);
    await close(tester, backend);
  });

  testWidgets('switching to French translates the screens', (tester) async {
    final backend = await openApp(tester);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FR'));
    await tester.pumpAndSettle();
    for (final word in ['Accueil', 'Réserver', 'Profil', 'Se déconnecter']) {
      expect(find.text(word), findsWidgets, reason: word);
    }
    expect(find.text('Sign out'), findsNothing);
    await close(tester, backend);
  });
}
