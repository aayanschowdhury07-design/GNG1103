import 'dart:math';

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DemoBackend b;
  setUp(() => b = DemoBackend(random: Random(1)));
  tearDown(() => b.dispose());

  BookingRequest req(String owner, {int minute = 930, String clin = 'osei', String? date}) => BookingRequest(
      clinicId: 'mg', serviceId: 'mg-fu', clinicianId: clin, date: date ?? b.today, minute: minute, patientName: 'Test', phone: '4165550142', owner: owner);

  /// The first day after today that Dr. Osei works (Mon to Fri).
  String nextOseiDay() => b.bookableDays.skip(1).firstWhere((d) => b.workingOn('osei', d));

  test('times and days are formatted for each language', () {
    expect(formatTime(930), '3:30 pm');
    expect(formatTime(540), '9:00 am');
    expect(formatTime(930, lang: 'fr'), '15 h 30');
    expect(shortDate('2026-10-29'), 'Thu Oct 29');
    expect(shortDate('2026-10-29', lang: 'fr'), 'jeu. 29 oct.');
    expect(dayLabel('2026-10-24', '2026-10-23'), 'Tomorrow');
    expect(longDay('2026-10-23', '2026-10-23'), 'Today, Friday Oct 23');
    expect(addDays('2026-12-31', 1), '2027-01-01');
  });

  test('times that already passed today cannot be booked', () {
    expect(b.slotState('osei', b.today, 600), SlotState.taken); // 10:00 has Lucie Fortin
    expect(b.slotState('lam', b.today, 570), SlotState.past); // 9:30 is before 9:41
    expect(b.slotState('daoud', b.today, 930), SlotState.blocked); // not in on the sample day
    expect(b.slotState('osei', addDays(b.today, -1), 990), SlotState.past); // yesterday
  });

  test('days after today follow each clinician’s weekly hours', () {
    final lamDays = {'Tue', 'Thu', 'Sat'};
    final inDay = b.bookableDays.skip(1).firstWhere((d) => lamDays.contains(weekdayOf(d)));
    final outDay = b.bookableDays.skip(1).firstWhere((d) => !lamDays.contains(weekdayOf(d)));
    expect(b.workingOn('lam', inDay), isTrue);
    expect(b.workingOn('lam', outDay), isFalse);
    expect(b.slotState('lam', outDay, 600), SlotState.blocked);
    expect(b.slotState('osei', nextOseiDay(), 600), SlotState.free); // the sample day's bookings don't carry over
  });

  test('a held slot is free for its holder and held for everyone else', () async {
    expect(await b.hold('osei', b.today, 930, owner: 'patient', length: const Duration(minutes: 5)), isTrue);
    expect(b.slotState('osei', b.today, 930, viewer: 'patient'), SlotState.free);
    expect(b.slotState('osei', b.today, 930, viewer: 'front desk'), SlotState.held);
    expect(await b.hold('osei', b.today, 930, owner: 'front desk', length: const Duration(minutes: 2)), isFalse);
  });

  test('two bookings for the same slot: one succeeds, the other is rejected', () async {
    await b.hold('osei', b.today, 930, owner: 'a', length: const Duration(minutes: 5));
    final first = await b.book(req('a'));
    final second = await b.book(req('b'));
    expect(first.outcome, BookingOutcome.booked);
    expect(first.appointment!.status, ApptStatus.confirmed); // phone-verified bookings start confirmed
    expect(second.outcome, BookingOutcome.holdExpired);
    expect(b.slotState('osei', b.today, 930), SlotState.taken);
  });

  test('the same time on another day is a different slot', () async {
    final later = nextOseiDay();
    await b.hold('osei', later, 930, owner: 'a', length: const Duration(minutes: 5));
    final r = await b.book(req('a', date: later));
    expect(r.outcome, BookingOutcome.booked);
    expect(r.appointment!.date, later);
    expect(b.slotState('osei', later, 930), SlotState.taken);
    expect(b.slotState('osei', b.today, 930), SlotState.free);
  });

  test('booking without a live hold is refused', () async {
    expect((await b.book(req('nobody'))).outcome, BookingOutcome.holdExpired);
  });

  test('a phone number gets at most 2 unconfirmed bookings', () async {
    await b.sendVerificationCode('416 555 0199');
    await b.sendVerificationCode('416 555 0199');
    expect(() => b.sendVerificationCode('416-555-0199'), throwsA(isA<RateLimitException>()));
  });

  test('each directory clinic reads its own schedule', () {
    expect(b.nextOpening('lp'), (date: b.today, minute: 690)); // Lakeshore: 11:30 with S. Whitlock
    expect(b.nextOpening('df'), (date: b.today, minute: 960)); // Dundas: 4:00 pm
    expect(b.nextOpening('qw'), isNull); // waitlist only
    expect(b.services('hm').single.short, 'Counselling, first session');
  });

  test('rescheduling moves the visit only to a slot the patient holds, on any day', () async {
    final mine = b.myAppointments().single, later = nextOseiDay();
    expect((await b.reschedule(mine.id, clinicianId: 'osei', date: later, minute: 600, owner: 'patient')).outcome, BookingOutcome.holdExpired);
    await b.hold('osei', later, 600, owner: 'patient', length: const Duration(minutes: 5));
    final moved = await b.reschedule(mine.id, clinicianId: 'osei', date: later, minute: 600, owner: 'patient');
    expect(moved.outcome, BookingOutcome.booked);
    expect((mine.date, mine.minute), (later, 600));
    expect(b.canCheckIn(mine), isFalse); // check-in opens on the day
    expect(b.slotState('osei', b.today, 540), SlotState.past); // the old 9:00 time is free again, but already passed
    expect(b.notifications().first.text, startsWith('Moved'));
  });

  test('joining the waitlist brings an offer for the freed 10:30 slot, and taking it moves the visit', () async {
    await b.joinWaitlist(WaitlistRequest(days: {weekdayOf(b.today)}, parts: const {DayPart.morning}));
    expect(b.pendingOffer(), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    expect(b.pendingOffer()!.minute, 630);
    expect(b.pendingOffer()!.date, b.today);
    await b.acceptOffer();
    expect(b.myAppointments().single.minute, 630);
    expect(b.pendingOffer(), isNull);
  });

  test('the form, sign-in and paying the balance', () async {
    final mine = b.myAppointments().single;
    await b.submitIntake(mine.id, const IntakeAnswers(visitType: 'Follow-up visit'));
    expect(mine.formsDone, isTrue);

    await b.signOut();
    expect(b.signedIn, isFalse);
    await b.sendSignInCode('416 555 0142');
    final code = RegExp(r'\d{6}').firstMatch(b.inbox.value!)!.group(0)!;
    expect(await b.signIn('416 555 0142', '000000'), isFalse);
    expect(await b.signIn('416 555 0142', code), isTrue);

    expect(b.balanceOwing, 40);
    expect(await b.payBalance(), 40);
    expect(b.balanceOwing, 0);
  });

  test('check-in gives a ticket and late cancellation follows the 24 h window', () async {
    final mine = b.myAppointments().single;
    expect(b.lateCancellation(mine.id), isTrue);
    expect(b.canCheckIn(mine), isTrue);
    final a = await b.checkIn(mine.id);
    expect(a.ticket, 'A-15');
    expect(a.status, ApptStatus.checkedIn);
  });
}
