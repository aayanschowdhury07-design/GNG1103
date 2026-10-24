import 'package:flutter/foundation.dart';

import 'models.dart';

/// Test backends (the sample data, the Firebase emulator) put texts here instead of
/// sending them, so the app can show an incoming-message banner and fill codes.
abstract interface class TestInbox {
  ValueNotifier<String?> get inbox;
}

/// Everything the apps ask of the server. Screens only talk to this interface.
///
/// [DemoBackend] implements it in memory with the prototype's sample data. A
/// FirebaseBackend (Firestore + Cloud Functions + Auth) will implement the same
/// interface, so the screens don't change when the real backend arrives.
/// Listeners are notified whenever data changes, the way Firestore pushes updates.
abstract class ClinicFlowBackend extends ChangeNotifier {
  /// The clinic's clock: real time, or the sample morning in demos and tests.
  ClinicClock get clock;
  String get today => clock.today;
  int get nowMinute => clock.minute;

  /// The days patients can book: today and the [bookingDays] - 1 after it.
  List<String> get bookableDays => daysFrom(today, bookingDays);

  // ---- clinic directory and setup data ----
  List<Clinic> get clinics;
  Clinic clinic(String id);
  List<Service> services(String clinicId);
  Service service(String id);
  List<Clinician> clinicians(String clinicId);
  Clinician clinician(String id);

  /// Straight-line distance from the patient, in km (one decimal).
  double distanceKm(Clinic c);

  /// The soonest time anyone can book online in the next two weeks, or null.
  ({String date, int minute})? nextOpening(String clinicId) {
    if (!clinic(clinicId).accepting) return null;
    final ids = services(clinicId).where((s) => s.online).expand((s) => s.clinicianIds).toSet();
    for (final d in bookableDays) {
      for (final m in slotMinutes) {
        if (ids.any((id) => slotState(id, d, m, viewer: 'directory') == SlotState.free)) return (date: d, minute: m);
      }
    }
    return null;
  }

  /// False when the clinician is not in at all on [date].
  bool workingOn(String clinicianId, String date);

  // ---- scheduling ----
  /// What [viewer] can do with a slot. A slot held by the viewer reads as free to them.
  SlotState slotState(String clinicianId, String date, int minute, {String? viewer});
  Hold? holdOf(String owner);

  /// Holds a slot for [owner]; false if someone else holds it or it's no longer free.
  Future<bool> hold(String clinicianId, String date, int minute, {required String owner, required Duration length});
  void releaseHolds(String owner);

  // ---- phone verification (guest booking) ----
  /// Texts a 6-digit code. Throws [RateLimitException] after 2 unconfirmed bookings.
  Future<void> sendVerificationCode(String phone);
  Future<bool> verifyCode(String phone, String code);

  /// The single write path for new bookings: one appointment per clinician and
  /// start time, and only while the caller still holds the slot.
  Future<BookingResult> book(BookingRequest request);

  // ---- the signed-in patient's visits ----
  /// Every visit on record for the patient, earliest first.
  List<Appointment> myAppointments();

  /// Visits still ahead (or under way today), earliest first. Past days drop off.
  List<Appointment> upcomingVisits() => myAppointments().where((a) => a.date.compareTo(today) >= 0).toList();

  /// Check-in opens on the day of the visit.
  bool canCheckIn(Appointment a) => a.date == today && (a.status == ApptStatus.booked || a.status == ApptStatus.confirmed || a.status == ApptStatus.late);
  Future<void> confirmVisit(String appointmentId);
  Future<void> cancelVisit(String appointmentId);
  Future<Appointment> checkIn(String appointmentId);
  int peopleAhead(String appointmentId);
  bool lateCancellation(String appointmentId);
  int get cancelWindowHours;

  /// Moves a visit to a slot the caller holds. Same guarantees as [book].
  Future<BookingResult> reschedule(String appointmentId, {required String clinicianId, required String date, required int minute, required String owner});
  Future<void> submitIntake(String appointmentId, IntakeAnswers answers);

  // ---- patient sign-in (booking never needs it) ----
  bool get signedIn;

  /// Texts or emails a sign-in code. Unlike booking codes, these don't count toward the booking limit.
  Future<void> sendSignInCode(String phoneOrEmail);
  Future<bool> signIn(String phoneOrEmail, String code);

  /// Face ID / fingerprint unlocks a sign-in saved on this device.
  Future<bool> signInWithDevice();
  Future<void> signOut();

  // ---- the patient's profile ----
  bool get smsConsent;
  String get smsConsentChangedOn;
  Future<void> setSmsConsent(bool on);
  List<FamilyMember> family();
  Future<FamilyMember> addFamilyMember({required String name, required String relationship, DateTime? born});

  // ---- waitlist ----
  WaitlistRequest? myWaitlist();
  Future<void> joinWaitlist(WaitlistRequest request);

  /// A freed slot currently held for this patient, if any.
  WaitlistOffer? pendingOffer();
  Future<void> acceptOffer();
  Future<void> declineOffer();
  int get offerHoldMinutes;

  // ---- notifications and history ----
  List<PatientNotice> notifications();
  List<PastVisit> visitHistory();
  double get balanceOwing;

  /// Pays everything owing; returns the amount paid.
  Future<double> payBalance();
}
