import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

/// Who is signed in and how they like the app on this device: language, theme, text size.
/// (Family members and text-message consent are records, so they live in the backend.)
/// The booking in progress lives here too, so every step reads the same draft.
class PatientSession extends ChangeNotifier {
  final String name = 'Priya Raman';
  final String phone = '+1 416 555 0142';

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

  /// Where booking starts: the patient's own clinic, otherwise the nearest one taking bookings.
  static String defaultClinic(ClinicFlowBackend b) {
    final home = b.clinics.where((c) => c.isHome).firstOrNull;
    if (home != null) return home.id;
    final open = b.clinics.where((c) => c.accepting).toList()..sort((x, y) => b.distanceKm(x).compareTo(b.distanceKm(y)));
    return (open.firstOrNull ?? b.clinics.first).id;
  }

  /// Set when moving an existing visit rather than booking a new one.
  String? rescheduling;
  String serviceId = '';
  String clinicianId = '';
  String? heldClinicianId;

  /// The day being booked ('2026-10-23') and the held start time on it.
  String date = '';
  int? minute;
  String who = 'Priya Raman';
  String? error;
  Appointment? lastBooked;

  /// The clinicians a time can be with: the chosen one, or all of them for "First available".
  List<String> clinicianIds(ClinicFlowBackend b) => clinicianId == 'any' ? b.service(serviceId).clinicianIds : [clinicianId];

  /// Is there a time anyone could be booked for on [day]?
  bool hasOpening(ClinicFlowBackend b, String day) =>
      slotMinutes.any((m) => clinicianIds(b).any((id) => b.slotState(id, day, m, viewer: owner) == SlotState.free));

  /// Opens on the first day with a time left, so nobody lands on a fully booked today.
  void _firstOpenDay(ClinicFlowBackend b) => date = b.bookableDays.firstWhere((d) => hasOpening(b, d), orElse: () => b.today);

  /// Starts over at [clinic] with its first online service and clinician.
  void start(ClinicFlowBackend b, String clinic, {String? keepWho}) {
    b.releaseHolds(owner);
    rescheduling = null;
    clinicId = clinic;
    final svc = b.services(clinic).firstWhere((s) => s.online);
    serviceId = svc.id;
    clinicianId = svc.clinicianIds.first;
    heldClinicianId = null;
    minute = null;
    error = null;
    who = keepWho ?? who;
    _firstOpenDay(b);
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
