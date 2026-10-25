import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

/// How the patient likes the app on this device: language, theme, text size. (Who they are,
/// their family and consent are records, so they live in the backend.) The booking in
/// progress lives here too, so every step reads the same draft.
class PatientSession extends ChangeNotifier {
  String lang = 'en';
  ThemeMode themeMode = ThemeMode.light;
  bool largeText = false;
  final BookingDraft draft = BookingDraft();

  Strings get s => Strings(lang);

  void setLang(String l) {
    lang = l;
    notifyListeners();
  }

  void setDark(bool on) {
    themeMode = on ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setLargeText(bool on) {
    largeText = on;
    notifyListeners();
  }
}

/// The booking being made, step by step. [clinicianId] may be 'any' (first available);
/// [heldClinicianId] is the clinician whose slot is actually held.
class BookingDraft extends ChangeNotifier {
  static const owner = 'patient';
  static const holdLength = Duration(minutes: 5);

  String clinicId = '';

  /// A clinic someone can book online right now.
  static bool canBook(ClinicFlowBackend b, Clinic c) => c.bookable && c.accepting && b.services(c.id).any((s) => s.online && s.clinicianIds.isNotEmpty);

  /// Where booking starts: the patient's own clinic, otherwise the nearest one taking
  /// bookings. Empty when no clinic is on ClinicFlow yet.
  static String defaultClinic(ClinicFlowBackend b) {
    final home = b.clinics.where((c) => c.isHome && canBook(b, c)).firstOrNull;
    if (home != null) return home.id;
    final open = b.clinics.where((c) => canBook(b, c)).toList()..sort(b.byDistance);
    return (open.firstOrNull ?? b.clinics.firstOrNull)?.id ?? '';
  }

  /// The clinic and service chosen are bookable online.
  bool get ready => clinicId.isNotEmpty && serviceId.isNotEmpty;

  /// Set when moving an existing visit rather than booking a new one.
  String? rescheduling;
  String serviceId = '';
  String clinicianId = '';
  String? heldClinicianId;

  /// The day being booked ('2026-10-23') and the held start time on it.
  String date = '';
  int? minute;

  /// Who the visit is for: '' is the patient themselves, otherwise a family member's name.
  String who = '';
  String? error;
  Appointment? lastBooked;

  /// The clinicians a time can be with: the chosen one, or all of them for "First available".
  List<String> clinicianIds(ClinicFlowBackend b) => clinicianId == 'any' ? b.service(serviceId).clinicianIds : [clinicianId];

  /// Is there a time anyone could be booked for on [day]?
  bool hasOpening(ClinicFlowBackend b, String day) =>
      slotMinutes.any((m) => clinicianIds(b).any((id) => b.slotState(id, day, m, viewer: owner) == SlotState.free));

  /// Opens on the first day with a time left, so nobody lands on a fully booked today.
  void _firstOpenDay(ClinicFlowBackend b) => date = b.bookableDays.firstWhere((d) => hasOpening(b, d), orElse: () => b.today);

  /// Starts over at [clinic] with its first online service and clinician. A clinic with
  /// nothing bookable online leaves the service empty; the booking screen says so.
  void start(ClinicFlowBackend b, String clinic, {String? keepWho}) {
    b.releaseHolds(owner);
    rescheduling = null;
    clinicId = clinic;
    final svc = clinic.isEmpty || !b.clinic(clinic).bookable ? null : b.services(clinic).where((s) => s.online && s.clinicianIds.isNotEmpty).firstOrNull;
    serviceId = svc?.id ?? '';
    clinicianId = svc?.clinicianIds.first ?? '';
    heldClinicianId = null;
    minute = null;
    error = null;
    who = keepWho ?? who;
    if (svc != null) _firstOpenDay(b);
    notifyListeners();
  }

  /// Change the time of [a]: same clinic, service and clinician, new slot.
  void startReschedule(ClinicFlowBackend b, Appointment a) {
    b.releaseHolds(owner);
    rescheduling = a.id;
    clinicId = a.clinicId;
    serviceId = a.serviceId;
    clinicianId = a.clinicianId;
    who = a.patientName;
    minute = null;
    heldClinicianId = null;
    error = null;
    _firstOpenDay(b);
    notifyListeners();
  }

  void pickService(ClinicFlowBackend b, String id) {
    serviceId = id;
    final svc = b.service(id);
    if (clinicianId != 'any' && !svc.clinicianIds.contains(clinicianId)) clinicianId = svc.clinicianIds.first;
    _firstOpenDay(b);
    _clearTime(b);
  }

  void pickClinician(ClinicFlowBackend b, String id) {
    clinicianId = id;
    if (!hasOpening(b, date)) _firstOpenDay(b);
    _clearTime(b);
  }

  void pickDay(ClinicFlowBackend b, String day) {
    date = day;
    _clearTime(b);
  }

  void pickWho(String name) {
    who = name;
    notifyListeners();
  }

  void _clearTime(ClinicFlowBackend b) {
    b.releaseHolds(owner);
    minute = null;
    heldClinicianId = null;
    error = null;
    notifyListeners();
  }

  /// Holds [m] on [date] with the chosen clinician, or the first free one for "First available".
  Future<void> pickTime(ClinicFlowBackend b, int m, Strings s) async {
    for (final id in clinicianIds(b)) {
      if (b.slotState(id, date, m, viewer: owner) == SlotState.free && await b.hold(id, date, m, owner: owner, length: holdLength)) {
        minute = m;
        heldClinicianId = id;
        error = null;
        notifyListeners();
        return;
      }
    }
    error = s.t('slotBusy');
    notifyListeners();
  }

  /// The hold ran out: the patient has to choose a time again.
  void holdExpired(Strings s) {
    minute = null;
    heldClinicianId = null;
    error = s.t('holdExpired');
    notifyListeners();
  }

  /// Booked: the hold is spent, so the time is cleared before any screen reacts to it.
  void finish(Appointment booked) {
    lastBooked = booked;
    minute = null;
    heldClinicianId = null;
    error = null;
    notifyListeners();
  }

  void setError(String? e) {
    error = e;
    notifyListeners();
  }
}
