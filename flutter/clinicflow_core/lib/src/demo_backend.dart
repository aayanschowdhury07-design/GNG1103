import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'backend.dart';
import 'models.dart';

/// In-memory backend seeded with the prototype's sample day at Maple Grove Clinic, plus four
/// other clinics in the ClinicFlow directory. The sample day is today: the clock starts at
/// 9:41 this morning, and the days after it follow each clinician's weekly hours.
/// Nothing leaves the device: texts appear in [inbox] instead of being sent.
class DemoBackend extends ClinicFlowBackend implements TestInbox {
  DemoBackend({ClinicClock? clock, math.Random? random})
      : clock = clock ?? ClinicClock.sampleMorning(),
        _random = random ?? math.Random() {
    _day0 = this.clock.today;
    here = (lat: 43.6745, lng: -79.3905);
    _seed();
    // expire holds as they run out, the way the server would
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _expireHolds());
  }

  @override
  final ClinicClock clock;
  final math.Random _random;
  late final Timer _ticker;

  /// The sample day: the date the clock started on.
  late final String _day0;

  /// Simulated incoming text messages on the patient's phone (demo only).
  @override
  final ValueNotifier<String?> inbox = ValueNotifier(null);
  @override
  bool get isTest => true;

  final _clinics = <Clinic>[];
  final _clinicians = <Clinician>[];
  final _services = <Service>[];
  final _hours = <String, WorkHours>{};
  final _blocks = <Block>[];
  final _appointments = <Appointment>[];
  final _holds = <String, Hold>{};
  final _codes = <String, String>{};
  final _unconfirmed = <String, int>{};
  int _nextId = 100, _nextTicket = 15;

  // the signed-in patient's own records
  bool _signedIn = true, _smsConsent = true;
  late String _consentDate;
  String? _signInCode;
  final _family = <FamilyMember>[FamilyMember(id: 'f1', name: 'Arjun Raman', relationship: 'Child', born: DateTime(2017, 4, 12))];
  final _notices = <PatientNotice>[];
  final _history = <PastVisit>[];
  WaitlistRequest? _waitlist;
  WaitlistOffer? _offer;
  final _intake = <String, IntakeAnswers>{};

  String get _clockLabel => formatTime(nowMinute);
  void _notify(String text, String channel, NoticeKind kind, [NoticeAction? action]) =>
      _notices.insert(0, PatientNotice(text: text, when: '$_clockLabel · $channel', kind: kind, action: action));

  /// "today at 3:30 pm", "tomorrow at 9:00 am", "Thu Oct 29 at 9:00 am".
  String _when(String date, int minute) => '${dayLabel(date, today, midSentence: true)} at ${formatTime(minute)}';

  // the sample patient, sharing her location near Yonge and St Clair
  var _profile = const PatientProfile(name: 'Priya Raman', phone: '+1 416 555 0142', email: 'priya.r@example.ca');

  @override
  void dispose() {
    _ticker.cancel();
    inbox.dispose();
    super.dispose();
  }

  @override
  int get cancelWindowHours => 24;

  // ---------------------------------------------------------------- directory
  @override
  List<Clinic> get clinics => List.unmodifiable(_clinics);
  @override
  Clinic clinic(String id) => _clinics.firstWhere((c) => c.id == id);
  @override
  List<Service> services(String clinicId) => _services.where((s) => s.clinicId == clinicId).toList();
  @override
  Service service(String id) => _services.firstWhere((s) => s.id == id);
  @override
  List<Clinician> clinicians(String clinicId) => _clinicians.where((c) => c.clinicId == clinicId).toList();
  @override
  Clinician clinician(String id) => _clinicians.firstWhere((c) => c.id == id);

  @override
  bool workingOn(String clinicianId, String date) => slotMinutes.any((m) => _offAt(clinicianId, date, m) == null);

  // ---------------------------------------------------------------- scheduling
  /// Why a clinician can't be booked at a time: a break or time off, or outside their hours.
  /// On the sample day everyone keeps the prototype's schedule, whatever weekday it falls on.
  String? _offAt(String clinicianId, String date, int minute) {
    final b = _blocks.where((b) => b.clinicianId == clinicianId && b.covers(date, minute)).firstOrNull;
    if (b != null) return b.type;
    if (date != _day0 && !(_hours[clinicianId] ?? WorkHours.weekdays9to5).covers(date, minute)) return 'Not in';
    return null;
  }

  Appointment? _apptAt(String clinicianId, String date, int minute) =>
      _appointments.where((a) => a.clinicianId == clinicianId && a.date == date && a.minute == minute && a.status.active).firstOrNull;
  String _key(String clinicianId, String date, int minute) => '$clinicianId@$date@$minute';
  Hold? _liveHold(String clinicianId, String date, int minute) {
    final h = _holds[_key(clinicianId, date, minute)];
    return h != null && h.live ? h : null;
  }

  @override
  SlotState slotState(String clinicianId, String date, int minute, {String? viewer}) {
    if (clock.passed(date, minute)) return SlotState.past;
    if (_offAt(clinicianId, date, minute) != null) return SlotState.blocked;
    if (_apptAt(clinicianId, date, minute) != null) return SlotState.taken;
    final h = _liveHold(clinicianId, date, minute);
    if (h != null && h.owner != viewer) return SlotState.held;
    return SlotState.free;
  }

  @override
  Hold? holdOf(String owner) => _holds.values.where((h) => h.owner == owner && h.live).firstOrNull;

  @override
  Future<bool> hold(String clinicianId, String date, int minute, {required String owner, required Duration length}) async {
    if (slotState(clinicianId, date, minute, viewer: owner) != SlotState.free) return false;
    _holds.removeWhere((_, h) => h.owner == owner); // one hold per person at a time
    _holds[_key(clinicianId, date, minute)] =
        Hold(clinicianId: clinicianId, date: date, minute: minute, owner: owner, expiresAt: DateTime.now().add(length));
    notifyListeners();
    return true;
  }

  @override
  void releaseHolds(String owner) {
    final before = _holds.length;
    _holds.removeWhere((_, h) => h.owner == owner);
    if (_holds.length != before) notifyListeners();
  }

  void _expireHolds() {
    final before = _holds.length;
    _holds.removeWhere((_, h) => !h.live);
    if (_holds.length != before) notifyListeners();
  }

  // ---------------------------------------------------------------- phone codes
  @override
  Future<void> sendVerificationCode(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if ((_unconfirmed[digits] ?? 0) >= 2) throw const RateLimitException();
    _unconfirmed[digits] = (_unconfirmed[digits] ?? 0) + 1;
    final code = (100000 + _random.nextInt(900000)).toString();
    _codes[digits] = code;
    inbox.value = 'ClinicFlow: $code is your verification code. Don\'t share it.';
  }

  @override
  Future<bool> verifyCode(String phone, String code) async =>
      _codes[phone.replaceAll(RegExp(r'\D'), '')] == code.trim();

  @override
  Future<BookingResult> book(BookingRequest r) async {
    final h = _liveHold(r.clinicianId, r.date, r.minute);
    if (h == null || h.owner != r.owner) return const BookingResult(BookingOutcome.holdExpired);
    if (_offAt(r.clinicianId, r.date, r.minute) != null || _apptAt(r.clinicianId, r.date, r.minute) != null) {
      return const BookingResult(BookingOutcome.slotTaken);
    }
    final digits = r.phone.replaceAll(RegExp(r'\D'), '');
    final appt = Appointment(
      id: 'APT-${_nextId++}',
      clinicId: r.clinicId,
      clinicianId: r.clinicianId,
      serviceId: r.serviceId,
      patientName: r.patientName,
      date: r.date,
      minute: r.minute,
      // the phone code is the confirmation, so a verified booking starts confirmed
      status: ApptStatus.confirmed,
      phoneLast4: digits.length >= 4 ? digits.substring(digits.length - 4) : null,
      mine: true,
      bookedByGuardian: r.bookedByGuardian,
    );
    _appointments.add(appt);
    _holds.remove(_key(r.clinicianId, r.date, r.minute));
    _unconfirmed[digits] = math.max(0, (_unconfirmed[digits] ?? 1) - 1);
    _codes.remove(digits);
    _signedIn = true; // the verified phone signs the guest in
    final c = clinic(r.clinicId);
    _notify('Booked${r.bookedByGuardian ? ' for ${r.patientName.split(' ').first}' : ''}: ${service(r.serviceId).short}, ${shortDate(r.date)}, ${formatTime(r.minute)} with ${clinician(r.clinicianId).short}${c.isHome ? '' : ' at ${c.name}'}.',
        'text and email', NoticeKind.update);
    notifyListeners();
    return BookingResult(BookingOutcome.booked, appt);
  }

  @override
  Future<BookingResult> reschedule(String id, {required String clinicianId, required String date, required int minute, required String owner}) async {
    final a = _appt(id);
    final h = _liveHold(clinicianId, date, minute);
    if (h == null || h.owner != owner) return const BookingResult(BookingOutcome.holdExpired);
    if (_offAt(clinicianId, date, minute) != null || _apptAt(clinicianId, date, minute) != null) return const BookingResult(BookingOutcome.slotTaken);
    final from = _when(a.date, a.minute);
    a
      ..clinicianId = clinicianId
      ..date = date
      ..minute = minute;
    _holds.remove(_key(clinicianId, date, minute));
    _notify('Moved: your visit is now ${_when(date, minute)} with ${clinician(clinicianId).short} (was $from).', 'push and text', NoticeKind.update);
    notifyListeners();
    return BookingResult(BookingOutcome.booked, a);
  }

  @override
  Future<void> submitIntake(String id, IntakeAnswers answers) async {
    _intake[id] = answers;
    _appt(id).formsDone = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------- sign-in
  @override
  bool get signedIn => _signedIn;

  @override
  Future<void> sendSignInCode(String phoneOrEmail) async {
    _signInCode = (100000 + _random.nextInt(900000)).toString();
    inbox.value = 'ClinicFlow: $_signInCode is your sign-in code.';
  }

  @override
  Future<bool> signIn(String phoneOrEmail, String code) async {
    if (code.trim() != _signInCode) return false;
    _signedIn = true;
    _signInCode = null;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> signInWithDevice() async {
    _signedIn = true;
    notifyListeners();
    return true;
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- profile
  @override
  PatientProfile? get profile => _signedIn ? _profile : null;

  @override
  Future<void> saveProfile({required String name, required String email}) async {
    _profile = PatientProfile(name: name.trim(), phone: _profile.phone, email: email.trim());
    notifyListeners();
  }

  @override
  Future<void> requestMyData(String kind) async {
    _notify(kind == 'delete' ? 'We received your request to delete your account. We’ll confirm by email within 30 days.' : 'We received your request for a copy of your data. It arrives by email within 30 days.',
        'email', NoticeKind.update);
    notifyListeners();
  }

  @override
  bool get smsConsent => _smsConsent;
  @override
  String get smsConsentChangedOn => _consentDate;

  @override
  Future<void> setSmsConsent(bool on) async {
    _smsConsent = on;
    _consentDate = today;
    notifyListeners();
  }

  @override
  List<FamilyMember> family() => List.unmodifiable(_family);

  @override
  Future<FamilyMember> addFamilyMember({required String name, required String relationship, DateTime? born}) async {
    final f = FamilyMember(id: 'f${_nextId++}', name: name, relationship: relationship, born: born);
    _family.add(f);
    notifyListeners();
    return f;
  }

  // ---------------------------------------------------------------- waitlist
  @override
  int get offerHoldMinutes => 15;
  @override
  WaitlistRequest? myWaitlist() => _waitlist;
  @override
  WaitlistOffer? pendingOffer() => _offer != null && _offer!.live ? _offer : null;

  /// On the sample day the 10:30 slot with Dr. Osei frees up, the person ahead of Priya
  /// lets their hold run out, and the offer moves to her a moment after she joins.
  @override
  Future<void> joinWaitlist(WaitlistRequest r) async {
    _waitlist = r;
    notifyListeners();
    final mine = upcomingVisits().where((a) => clinic(a.clinicId).isHome && a.status.upcoming).firstOrNull;
    if (mine == null) return;
    Timer(const Duration(seconds: 2), () {
      const slot = 630;
      final fits = r.days.contains(weekdayOf(_day0)) && r.parts.contains(DayPart.of(slot)) && (r.clinicianId == null || r.clinicianId == 'osei');
      if (!fits || slotState('osei', _day0, slot) != SlotState.free || _offer != null) return;
      _offer = WaitlistOffer(clinicianId: 'osei', date: _day0, minute: slot, appointmentId: mine.id, expiresAt: DateTime.now().add(Duration(minutes: offerHoldMinutes)));
      _notify('A time opened up: ${_when(_day0, slot)} with Dr. Kwame Osei. It’s held for you for $offerHoldMinutes minutes.', 'push and text', NoticeKind.offer, NoticeAction.offer);
      inbox.value = 'ClinicFlow: a time opened up ${_when(_day0, slot)} with Dr. Osei. Open the app within $offerHoldMinutes minutes to take it.';
      notifyListeners();
    });
  }

  @override
  Future<void> acceptOffer() async {
    final o = pendingOffer();
    if (o == null) return;
    final a = _appt(o.appointmentId), from = _when(a.date, a.minute);
    a
      ..clinicianId = o.clinicianId
      ..date = o.date
      ..minute = o.minute;
    _offer = null;
    _waitlist = null;
    _notify('Moved: your visit is now ${_when(o.date, o.minute)} with ${clinician(o.clinicianId).short} (was $from). Your old time went to the next person on the waitlist.', 'push and text', NoticeKind.update);
    notifyListeners();
  }

  @override
  Future<void> declineOffer() async {
    _offer = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- notifications and history
  @override
  List<PatientNotice> notifications() => List.unmodifiable(_notices);
  @override
  List<PastVisit> visitHistory() => List.unmodifiable(_history);
  @override
  double get balanceOwing => _history.fold(0, (t, v) => t + v.owing);

  @override
  Future<double> payBalance() async {
    final paid = balanceOwing;
    for (final v in _history) {
      v.owing = 0;
    }
    _notify('Paid \$${paid.toStringAsFixed(2)}. Your receipt was emailed.', 'email', NoticeKind.update);
    notifyListeners();
    return paid;
  }

  // ---------------------------------------------------------------- my visits
  @override
  List<Appointment> myAppointments() => _appointments.where((a) => a.mine).toList()..sort(Appointment.byTime);

  Appointment _appt(String id) => _appointments.firstWhere((a) => a.id == id);

  @override
  Future<void> confirmVisit(String id) async {
    final a = _appt(id);
    if (a.status == ApptStatus.booked) {
      a.status = ApptStatus.confirmed;
      notifyListeners();
    }
  }

  @override
  bool lateCancellation(String id) => clock.hoursUntil(_appt(id).date, _appt(id).minute) < cancelWindowHours;

  @override
  Future<void> cancelVisit(String id) async {
    final a = _appt(id)..status = ApptStatus.cancelled;
    _notify('Your visit ${_when(a.date, a.minute)} is cancelled. The time was offered to the waitlist.', 'push', NoticeKind.notice);
    notifyListeners();
  }

  @override
  Future<Appointment> checkIn(String id) async {
    final a = _appt(id);
    a.ticket ??= 'A-${_nextTicket++}';
    a.status = ApptStatus.checkedIn;
    a.checkedInAt = nowMinute;
    _notify("You're checked in. Ticket ${a.ticket}.", 'push', NoticeKind.update);
    notifyListeners();
    return a;
  }

  @override
  int peopleAhead(String id) {
    final a = _appt(id);
    int n(String? t) => int.tryParse((t ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0;
    return _appointments
        .where((x) => x != a && x.date == a.date && x.clinicianId == a.clinicianId && x.status == ApptStatus.waiting && n(x.ticket) < n(a.ticket))
        .length;
  }

  // ---------------------------------------------------------------- sample data
  void _seed() {
    final day0 = _day0;
    String ago(int n) => addDays(day0, -n);
    _consentDate = ago(7);
    _notices.addAll([
      const PatientNotice(text: 'Reminder: Physio today 9:00 am with Dr. Osei. Tap to confirm.', when: 'Yesterday 9:00 am · push, then text', kind: NoticeKind.reminder, action: NoticeAction.confirm),
      const PatientNotice(text: 'Please complete your reason-for-visit form before your visit.', when: 'Yesterday 9:01 am · text', kind: NoticeKind.todo, action: NoticeAction.intake),
      PatientNotice(text: 'Reminder: Physio on ${shortDate(day0)} at 9:00 am with Dr. Osei.', when: '2 days ago 9:00 am · push', kind: NoticeKind.reminder),
      PatientNotice(text: 'Booked: Physio, ${shortDate(day0)}, 9:00 am. Manage your visit any time from this link.', when: '${recordDate(ago(7))} · text and email', kind: NoticeKind.update),
    ]);
    _history.addAll([
      PastVisit(date: ago(14), service: 'Physiotherapy · follow-up', clinician: 'Dr. Kwame Osei', clinic: 'Maple Grove Clinic', fee: 95, owing: 0, who: 'Priya Raman'),
      PastVisit(date: ago(28), service: 'Physiotherapy · initial assessment', clinician: 'Dr. Kwame Osei', clinic: 'Maple Grove Clinic', fee: 130, owing: 40, who: 'Priya Raman'),
      PastVisit(date: ago(40), service: 'Chiropractic · adjustment', clinician: 'Dr. Rania Daoud', clinic: 'Maple Grove Clinic', fee: 70, owing: 0, who: 'Arjun Raman'),
      PastVisit(date: ago(110), service: 'Physiotherapy · follow-up', clinician: 'Sam Whitlock, PT', clinic: 'Lakeshore Physio', fee: 90, owing: 0, who: 'Priya Raman'),
    ]);
    _clinics.addAll(const [
      Clinic(id: 'mg', initials: 'MG', name: 'Maple Grove Clinic', address: '214 Elm Ave', kind: 'Physiotherapy, chiropractic', lat: 43.6807, lng: -79.3838, isHome: true,
          notice: 'Parking lot B is closed this week. Street parking on Elm Ave is free for 2 hours.'),
      Clinic(id: 'df', initials: 'DF', name: 'Dundas Family Health', address: '620 Bay St', kind: 'Family practice, walk-in', lat: 43.6600, lng: -79.3870),
      Clinic(id: 'lp', initials: 'LP', name: 'Lakeshore Physio', address: '45 St Clair Ave W', kind: 'Physiotherapy', lat: 43.6878, lng: -79.3985),
      Clinic(id: 'qw', initials: 'QW', name: 'Queen West Rehab', address: '215 Queen St W', kind: 'Rehab, massage', lat: 43.6505, lng: -79.3885, accepting: false),
      Clinic(id: 'hm', initials: 'HM', name: 'Harbour Mind Wellness', address: '25 Queens Quay E', kind: 'Mental health, counselling', lat: 43.6413, lng: -79.3760),
    ]);
    _clinicians.addAll(const [
      Clinician(id: 'osei', clinicId: 'mg', name: 'Dr. Kwame Osei', short: 'Dr. Osei', role: 'Physiotherapist', roleFr: 'Physiothérapeute'),
      Clinician(id: 'lam', clinicId: 'mg', name: 'Mei Lam, PT', short: 'M. Lam', role: 'Physiotherapist', roleFr: 'Physiothérapeute'),
      Clinician(id: 'daoud', clinicId: 'mg', name: 'Dr. Rania Daoud', short: 'Dr. Daoud', role: 'Chiropractor', roleFr: 'Chiropraticienne'),
      Clinician(id: 'df-rahman', clinicId: 'df', name: 'Dr. Aisha Rahman', short: 'Dr. Rahman', role: 'Family physician', roleFr: 'Médecin de famille'),
      Clinician(id: 'df-tran', clinicId: 'df', name: 'Dr. Paul Tran', short: 'Dr. Tran', role: 'Family physician', roleFr: 'Médecin de famille'),
      Clinician(id: 'lp-whitlock', clinicId: 'lp', name: 'Sam Whitlock, PT', short: 'S. Whitlock', role: 'Physiotherapist', roleFr: 'Physiothérapeute'),
      Clinician(id: 'lp-patel', clinicId: 'lp', name: 'Nora Patel, PT', short: 'N. Patel', role: 'Physiotherapist', roleFr: 'Physiothérapeute'),
      Clinician(id: 'qw-moreau', clinicId: 'qw', name: 'Luc Moreau, RMT', short: 'L. Moreau', role: 'Massage therapist', roleFr: 'Massothérapeute'),
      Clinician(id: 'hm-mensah', clinicId: 'hm', name: 'Grace Mensah, RP', short: 'G. Mensah', role: 'Psychotherapist', roleFr: 'Psychothérapeute'),
    ]);
    // weekly hours for the days after the sample day (everyone else: Mon to Fri, 9 to 5)
    _hours.addAll(const {
      'lam': WorkHours(days: {'Tue', 'Thu', 'Sat'}, start: 540, end: 1020),
      'daoud': WorkHours(days: {'Thu'}, start: 540, end: 1020),
    });
    _services.addAll(const [
      Service(id: 'mg-fu', clinicId: 'mg', name: 'Physiotherapy · follow-up', nameFr: 'Physiothérapie · suivi', short: 'Physio follow-up', minutes: 30, who: 'Returning patients', whoFr: 'Patients déjà suivis', clinicianIds: ['osei', 'lam']),
      Service(id: 'mg-ia', clinicId: 'mg', name: 'Physiotherapy · initial assessment', nameFr: 'Physiothérapie · évaluation initiale', short: 'Initial assessment', minutes: 45, who: 'New and returning', whoFr: 'Nouveaux patients et patients suivis', clinicianIds: ['osei', 'lam']),
      Service(id: 'mg-ch', clinicId: 'mg', name: 'Chiropractic · adjustment', nameFr: 'Chiropratique · ajustement', short: 'Chiro adjustment', minutes: 20, who: 'New and returning', whoFr: 'Nouveaux patients et patients suivis', clinicianIds: ['daoud']),
      Service(id: 'df-rv', clinicId: 'df', name: 'Family doctor · regular visit', nameFr: 'Médecin de famille · visite régulière', short: 'Family doctor visit', minutes: 15, who: 'Registered and new patients', whoFr: 'Patients inscrits et nouveaux patients', clinicianIds: ['df-rahman', 'df-tran']),
      Service(id: 'df-rx', clinicId: 'df', name: 'Prescription renewal', nameFr: 'Renouvellement d’ordonnance', short: 'Prescription renewal', minutes: 15, who: 'Registered patients', whoFr: 'Patients inscrits', clinicianIds: ['df-rahman', 'df-tran']),
      Service(id: 'lp-as', clinicId: 'lp', name: 'Physiotherapy · assessment', nameFr: 'Physiothérapie · évaluation', short: 'Physio assessment', minutes: 45, who: 'New patients', whoFr: 'Nouveaux patients', clinicianIds: ['lp-whitlock', 'lp-patel']),
      Service(id: 'lp-tx', clinicId: 'lp', name: 'Physiotherapy · treatment', nameFr: 'Physiothérapie · traitement', short: 'Physio treatment', minutes: 30, who: 'Returning patients', whoFr: 'Patients déjà suivis', clinicianIds: ['lp-whitlock', 'lp-patel']),
      Service(id: 'qw-ms', clinicId: 'qw', name: 'Massage therapy · 60 min', nameFr: 'Massothérapie · 60 min', short: 'Massage', minutes: 60, who: 'Waitlist only', whoFr: 'Liste d’attente seulement', clinicianIds: ['qw-moreau']),
      Service(id: 'hm-cs', clinicId: 'hm', name: 'Counselling · first session', nameFr: 'Counseling · première séance', short: 'Counselling, first session', minutes: 50, who: 'New clients', whoFr: 'Nouveaux clients', clinicianIds: ['hm-mensah']),
    ]);
    // the sample day's breaks and time off
    _blocks.addAll([
      Block(clinicianId: 'lam', type: 'Break', minutes: const {660}, date: day0),
      Block(clinicianId: 'lam', type: 'Not in', minutes: const {840, 870, 900, 930, 960, 990}, date: day0),
      Block(clinicianId: 'osei', type: 'Break', minutes: const {780}, date: day0),
      Block(clinicianId: 'daoud', type: 'Not in', date: day0),
    ]);
    // Maple Grove's day (the same patients as the prototype)
    var i = 1;
    Appointment mg(String name, String clin, int minute, String svc, ApptStatus st,
            {bool forms = true, String? phone, String? ticket, bool mine = false}) =>
        Appointment(id: 'APT-${20900 + i++}', clinicId: 'mg', clinicianId: clin, serviceId: svc, patientName: name, date: day0, minute: minute, status: st, formsDone: forms, phoneLast4: phone, ticket: ticket, mine: mine);
    _appointments.addAll([
      mg('Priya Raman', 'osei', 540, 'mg-fu', ApptStatus.booked, forms: false, phone: '0142', mine: true),
      mg('Marcus Chen', 'osei', 570, 'mg-fu', ApptStatus.late, phone: '2201'),
      mg('An Nguyen', 'lam', 540, 'mg-ia', ApptStatus.inVisit, ticket: 'A-14', phone: '6634'),
      mg('Lucie Fortin', 'osei', 600, 'mg-fu', ApptStatus.confirmed, phone: '7788'),
      mg('Raj Singh', 'lam', 600, 'mg-fu', ApptStatus.booked, forms: false, phone: '5530'),
      mg('Jordan Tremblay', 'osei', 660, 'mg-fu', ApptStatus.confirmed, phone: '4410'),
      mg('Daniel Okafor', 'osei', 690, 'mg-fu', ApptStatus.booked, phone: '9921'),
      mg('Tara Brown', 'lam', 690, 'mg-fu', ApptStatus.confirmed, phone: '3307'),
      mg('Ella Moore', 'lam', 810, 'mg-ia', ApptStatus.confirmed, forms: false, phone: '1185'),
      mg('Hana Sato', 'osei', 840, 'mg-fu', ApptStatus.confirmed, phone: '2290'),
      mg('Victor Diaz', 'osei', 900, 'mg-ia', ApptStatus.booked, forms: false, phone: '6071'),
    ]);
    // the other directory clinics: on the sample day everything is booked except these times
    const open = <String, List<int>>{
      'df-rahman': [960],
      'df-tran': [960, 990],
      'lp-whitlock': [690],
      'lp-patel': [840, 870, 930],
      'qw-moreau': [],
      'hm-mensah': [780, 930],
    };
    open.forEach((clin, free) {
      final c = clinician(clin);
      for (final m in slotMinutes.where((m) => !free.contains(m))) {
        _appointments.add(Appointment(id: '$clin-$m', clinicId: c.clinicId, clinicianId: clin, serviceId: '', patientName: '(booked)', date: day0, minute: m));
      }
    });
  }
}
