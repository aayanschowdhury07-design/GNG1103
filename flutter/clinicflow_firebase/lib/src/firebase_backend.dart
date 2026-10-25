import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'firebase_connect.dart';

/// ClinicFlow on Firebase: Firestore for the data, Authentication for phone sign-in.
///
/// Layout (see the data plan):
///   clinics/{clinic}                         directory profile
///     clinicians/{id}, services/{id}, blocks/{id}
///     appointments/{id}                      full records with their date; a patient reads only their own
///     slots/{clinician_date_minute}          "taken" markers, no names: the double-booking guard
///     holds/{clinician_date_minute}          5-minute holds while someone books
///     queue/{date_ticket}                    ticket numbers only, like the waiting-room board
///     counters/tickets-{date}                next ticket number, starting over each day
///   patients/{uid}                           consent, waitlist; family/, notices/, history/, offers/
///
/// The app only listens to the days it can show (today and the next two weeks), so the data
/// it downloads doesn't grow with the clinic's history. Before going live, booking, offers and
/// the audit log move into Cloud Functions.
class FirebaseBackend extends ClinicFlowBackend implements TestInbox {
  FirebaseBackend._(this._db, this._auth, this._emulatorHost, this.clock) : _session = _randomId();

  /// Connects to a real Firebase project, using the options `flutterfire configure` generated
  /// (lib/firebase_options.dart in the app).
  static Future<FirebaseBackend> startProject(FirebaseOptions options, {ClinicClock? clock}) async {
    final (db, auth) = await connectFirebase(options: options);
    final b = FirebaseBackend._(db, auth, null, clock ?? ClinicClock.real());
    await b._start();
    return b;
  }

  /// Connects to the local emulators (project "demo-clinicflow": never reaches the cloud).
  /// [clock] can start at the seeded sample morning, so the sample day plays out at any hour.
  static Future<FirebaseBackend> startEmulators({String host = 'localhost', ClinicClock? clock}) async {
    final (db, auth) = await connectFirebase(emulatorHost: host);
    final b = FirebaseBackend._(db, auth, host, clock ?? ClinicClock.real());
    await b._start();
    return b;
  }

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final String? _emulatorHost;

  /// Distinguishes this device's holds from another device signed in as the same person.
  final String _session;
  static String _randomId() => List.generate(12, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[math.Random().nextInt(36)]).join();

  @override
  final ValueNotifier<String?> inbox = ValueNotifier(null);

  @override
  final ClinicClock clock;
  @override
  int get cancelWindowHours => 24;
  @override
  int get offerHoldMinutes => 15;

  // ---------------------------------------------------------------- caches kept live by listeners
  final _subs = <StreamSubscription<dynamic>>[];
  final _daySubs = <StreamSubscription<dynamic>>[];
  final _patientSubs = <StreamSubscription<dynamic>>[];
  var _clinics = <Clinic>[];
  final _clinicians = <String, Clinician>{};
  final _services = <String, Service>{};
  final _serviceOrder = <String, int>{};
  var _blocks = <Block>[]; // breaks, time off: set by the clinic
  final _hours = <String, WorkHours>{}; // each clinician's working days and hours, from setup

  final _firstClinics = Completer<void>(), _firstServices = Completer<void>(), _firstClinicians = Completer<void>();
  static void _done(Completer<void> c) => c.isCompleted ? null : c.complete();

  /// The day the date-bound listeners (slots, holds, queue) were opened for.
  String _watchedDay = '';
  var _taken = <String>{}; // "clinic|clinician_date_minute"
  var _holds = <String, Map<String, dynamic>>{}; // "clinic|clinician_date_minute" -> {owner, expiresAt, ...}
  var _queue = <Map<String, dynamic>>[];
  var _mine = <Appointment>[];
  final _apptClinic = <String, String>{};
  Map<String, dynamic> _patient = const {};
  var _family = <FamilyMember>[];
  var _notices = <PatientNotice>[];
  var _history = <PastVisit>[];
  final _historyIds = <PastVisit, String>{};
  var _offers = <(String, WaitlistOffer)>[];
  Timer? _ticker;
  ConfirmationResult? _pendingPhone;

  String _clinicOf(DocumentSnapshot d) => d.reference.parent.parent!.id;
  DocumentReference<Map<String, dynamic>> _clinicDoc(String id) => _db.collection('clinics').doc(id);
  static String _slotKey(String clinicianId, String date, int minute) => '${clinicianId}_${date}_$minute';

  Future<void> _start() async {
    // signed-out visitors still browse the directory and book: they get an anonymous session
    if (_auth.currentUser == null) await _auth.signInAnonymously();
    _subs
      ..add(_db.collection('clinics').snapshots().listen((q) {
        _clinics = [
          for (final d in q.docs)
            Clinic(
              // patients book clinics that finished setup and were approved by ClinicFlow, and
              // find them in the directory if the clinic chose to be listed
              bookable: d.data()['ready'] != false && d.data()['approval'] == 'approved',
              listed: d.data()['ready'] != false && d.data()['listed'] != false && d.data()['approval'] == 'approved',
              id: d.id,
              // every field goes through data(): d['missing'] throws, and one half-set-up clinic
              // must not stop the whole directory from loading
              initials: d.data()['initials'] ?? '',
              name: d.data()['name'] ?? '',
              address: d.data()['address'] ?? '',
              kind: d.data()['kind'] ?? '',
              lat: (d.data()['lat'] as num? ?? 0).toDouble(),
              lng: (d.data()['lng'] as num? ?? 0).toDouble(),
              accepting: d.data()['accepting'] ?? true,
              isHome: d.data()['isHome'] ?? false,
              notice: d.data()['notice'],
            ),
        ];
        _done(_firstClinics);
        notifyListeners();
      }))
      ..add(_db.collectionGroup('clinicians').snapshots().listen((q) {
        _clinicians
          ..clear()
          ..addAll({
            for (final d in q.docs)
              d.id: Clinician(
                id: d.id,
                clinicId: _clinicOf(d),
                name: d.data()['name'] ?? '',
                short: d.data()['short'] ?? d.data()['name'] ?? '',
                role: d.data()['role'] ?? '',
                roleFr: d.data()['roleFr'] ?? '',
              ),
          });
        // working days and hours from the setup wizard; clinicians without them work every day
        _hours
          ..clear()
          ..addAll({
            for (final d in q.docs)
              if (d.data()['days'] is List)
                d.id: WorkHours(days: Set<String>.from(d.data()['days']), start: d.data()['start'] ?? 0, end: d.data()['end'] ?? 24 * 60),
          });
        _done(_firstClinicians);
        notifyListeners();
      }))
      ..add(_db.collectionGroup('services').snapshots().listen((q) {
        // the order the clinic listed its services in during setup
        _serviceOrder
          ..clear()
          ..addAll({for (final d in q.docs) d.id: (d.data()['order'] as int?) ?? 99});
        _services
          ..clear()
          ..addAll({
            for (final d in q.docs)
              d.id: Service(
                id: d.id,
                clinicId: _clinicOf(d),
                name: d.data()['name'] ?? '',
                nameFr: d.data()['nameFr'] ?? '',
                short: d.data()['short'] ?? d.data()['name'] ?? '',
                minutes: d.data()['minutes'] ?? 30,
                online: d.data()['online'] ?? true,
                who: d.data()['who'] ?? '',
                whoFr: d.data()['whoFr'] ?? '',
                clinicianIds: List<String>.from(d.data()['clinicianIds'] ?? const []),
              ),
          });
        _done(_firstServices);
        notifyListeners();
      }))
      ..add(_db.collectionGroup('blocks').snapshots().listen((q) {
        _blocks = [
          for (final d in q.docs)
            Block(
              clinicianId: d.data()['clinicianId'] ?? '',
              type: d.data()['type'] ?? 'Unavailable',
              minutes: d.data()['minutes'] == null ? null : Set<int>.from(d.data()['minutes']),
              date: d.data()['date'],
            ),
        ];
        notifyListeners();
      }))
      ..add(_auth.authStateChanges().listen(_watchPatient));
    _watchDays();
    // screens look clinics up by id, so wait for the directory's first answer before the first
    // frame. It may well be empty (no clinic approved yet): the app says so instead of failing.
    await Future.wait([_firstClinics.future, _firstServices.future, _firstClinicians.future]).timeout(const Duration(seconds: 15), onTimeout: () => const []);
    // holds expire on the clock, not on a database change; at midnight the days shown move on
    var live = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (today != _watchedDay) _watchDays();
      final now = _holdsLive();
      if (now != live) {
        live = now;
        notifyListeners();
      }
    });
  }

  /// Listens to the bookable days only: taken slots and holds from today to two weeks out,
  /// and today's waiting-room queue. Called again when the date changes.
  void _watchDays() {
    for (final s in _daySubs) {
      s.cancel();
    }
    _daySubs.clear();
    final from = today, to = addDays(today, bookingDays - 1);
    _watchedDay = from;
    _daySubs
      ..add(_db.collectionGroup('slots').where('date', isGreaterThanOrEqualTo: from).where('date', isLessThanOrEqualTo: to).snapshots().listen((q) {
        _taken = {for (final d in q.docs) '${_clinicOf(d)}|${d.id}'};
        notifyListeners();
      }))
      ..add(_db.collectionGroup('holds').where('date', isGreaterThanOrEqualTo: from).snapshots().listen((q) {
        _holds = {for (final d in q.docs) '${_clinicOf(d)}|${d.id}': d.data()};
        notifyListeners();
      }))
      ..add(_db.collectionGroup('queue').where('date', isEqualTo: from).snapshots().listen((q) {
        _queue = [for (final d in q.docs) {...d.data(), 'clinicId': _clinicOf(d)}];
        notifyListeners();
      }));
  }

  int _holdsLive() => _holds.values.where((h) => (h['expiresAt'] as int) > DateTime.now().millisecondsSinceEpoch).length;

  /// Subscribes to the signed-in patient's own records; anonymous visitors have none.
  void _watchPatient(User? user) {
    for (final s in _patientSubs) {
      s.cancel();
    }
    _patientSubs.clear();
    _mine = [];
    _patient = const {};
    _family = [];
    _notices = [];
    _history = [];
    _offers = [];
    notifyListeners();
    if (user == null || user.isAnonymous) return;
    final me = _db.collection('patients').doc(user.uid);
    _patientSubs
      ..add(_db.collectionGroup('appointments').where('patientUid', isEqualTo: user.uid).snapshots().listen((q) {
        _mine = [
          for (final d in q.docs)
            Appointment(
              id: d.id,
              clinicId: _clinicOf(d),
              clinicianId: d['clinicianId'],
              serviceId: d['serviceId'],
              patientName: d['patientName'],
              date: d.data()['date'] ?? today,
              minute: d['minute'],
              status: ApptStatus.values.byName(d['status']),
              ticket: d.data()['ticket'],
              formsDone: d.data()['formsDone'] ?? false,
              phoneLast4: d.data()['phoneLast4'],
              mine: true,
              bookedByGuardian: d.data()['bookedByGuardian'] ?? false,
            )..checkedInAt = d.data()['checkedInAt'],
        ]..sort(Appointment.byTime);
        for (final d in q.docs) {
          _apptClinic[d.id] = _clinicOf(d);
        }
        notifyListeners();
      }))
      ..add(me.snapshots().listen((d) {
        _patient = d.data() ?? const {};
        notifyListeners();
      }))
      ..add(me.collection('family').snapshots().listen((q) {
        _family = [
          for (final d in q.docs)
            FamilyMember(id: d.id, name: d['name'], relationship: d['relationship'], born: d.data()['born'] == null ? null : DateTime.parse(d['born'])),
        ];
        notifyListeners();
      }))
      ..add(me.collection('notices').orderBy('at', descending: true).snapshots().listen((q) {
        _notices = [
          for (final d in q.docs)
            PatientNotice(
              text: d['text'],
              when: d['when'],
              kind: NoticeKind.values.byName(d['kind']),
              action: d.data()['action'] == null ? null : NoticeAction.values.byName(d['action']),
            ),
        ];
        notifyListeners();
      }))
      ..add(me.collection('history').orderBy('order').snapshots().listen((q) {
        _historyIds.clear();
        _history = [
          for (final d in q.docs)
            PastVisit(
              date: d['date'],
              service: d['service'],
              clinician: d['clinician'],
              clinic: d['clinic'],
              fee: (d['fee'] as num).toDouble(),
              owing: (d['owing'] as num).toDouble(),
              who: d['who'],
            ),
        ];
        for (var i = 0; i < q.docs.length; i++) {
          _historyIds[_history[i]] = q.docs[i].id;
        }
        notifyListeners();
      }))
      ..add(me.collection('offers').snapshots().listen((q) {
        _offers = [
          for (final d in q.docs)
            (
              d.id,
              WaitlistOffer(
                clinicianId: d['clinicianId'],
                date: d.data()['date'] ?? today,
                minute: d['minute'],
                appointmentId: d['appointmentId'],
                expiresAt: DateTime.fromMillisecondsSinceEpoch(d['expiresAt']),
              ),
            ),
        ];
        notifyListeners();
      }));
  }

  @override
  void dispose() {
    for (final s in [..._subs, ..._daySubs, ..._patientSubs]) {
      s.cancel();
    }
    _ticker?.cancel();
    inbox.dispose();
    super.dispose();
  }

  String? get _uid => _auth.currentUser?.uid;
  DocumentReference<Map<String, dynamic>> get _me => _db.collection('patients').doc(_uid);
  String _clock() => formatTime(nowMinute);

  Future<void> _notify(String text, String channel, NoticeKind kind, [NoticeAction? action]) => _me.collection('notices').add({
        'text': text,
        'when': '${_clock()} · $channel',
        'kind': kind.name,
        'action': action?.name,
        'at': DateTime.now().millisecondsSinceEpoch,
      });

  // ---------------------------------------------------------------- directory
  @override
  List<Clinic> get clinics => List.unmodifiable(_clinics.where((c) => c.listed).map(_withHome));
  @override
  Clinic clinic(String id) => _withHome(_clinics.firstWhere((c) => c.id == id));

  /// "Your clinic" is the patient's own: the one they first booked at.
  Clinic _withHome(Clinic c) => c.withHome(c.id == _patient['homeClinic']);

  @override
  List<Service> services(String clinicId) =>
      _services.values.where((s) => s.clinicId == clinicId).toList()..sort((a, b) => (_serviceOrder[a.id] ?? 99).compareTo(_serviceOrder[b.id] ?? 99));
  @override
  Service service(String id) => _services[id]!;
  @override
  List<Clinician> clinicians(String clinicId) => _clinicians.values.where((c) => c.clinicId == clinicId).toList();
  @override
  Clinician clinician(String id) => _clinicians[id]!;

  /// A break or time off, or outside the clinician's working days and hours.
  bool _off(String clinicianId, String date, int minute) =>
      _blocks.any((b) => b.clinicianId == clinicianId && b.covers(date, minute)) || !(_hours[clinicianId]?.covers(date, minute) ?? true);

  @override
  bool workingOn(String clinicianId, String date) => slotMinutes.any((m) => !_off(clinicianId, date, m));

  // ---------------------------------------------------------------- scheduling
  String _owner(String owner) => '$owner#$_session';

  @override
  SlotState slotState(String clinicianId, String date, int minute, {String? viewer}) {
    if (clock.passed(date, minute)) return SlotState.past;
    if (_off(clinicianId, date, minute)) return SlotState.blocked;
    final key = '${_clinicians[clinicianId]?.clinicId}|${_slotKey(clinicianId, date, minute)}';
    if (_taken.contains(key)) return SlotState.taken;
    final h = _holds[key];
    if (h != null && (h['expiresAt'] as int) > DateTime.now().millisecondsSinceEpoch && h['owner'] != (viewer == null ? null : _owner(viewer))) {
      return SlotState.held;
    }
    return SlotState.free;
  }

  @override
  Hold? holdOf(String owner) {
    final me = _owner(owner), now = DateTime.now().millisecondsSinceEpoch;
    for (final e in _holds.entries) {
      if (e.value['owner'] == me && (e.value['expiresAt'] as int) > now) {
        return Hold(
          clinicianId: e.value['clinicianId'],
          date: e.value['date'] ?? today,
          minute: e.value['minute'],
          owner: owner,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(e.value['expiresAt']),
        );
      }
    }
    return null;
  }

  @override
  Future<bool> hold(String clinicianId, String date, int minute, {required String owner, required Duration length}) async {
    if (slotState(clinicianId, date, minute, viewer: owner) != SlotState.free) return false;
    final clinicId = clinician(clinicianId).clinicId, me = _owner(owner), key = _slotKey(clinicianId, date, minute);
    final holdRef = _clinicDoc(clinicId).collection('holds').doc(key), slotRef = _clinicDoc(clinicId).collection('slots').doc(key);
    releaseHolds(owner); // one hold per person at a time
    return _db.runTransaction((tx) async {
      final slot = await tx.get(slotRef), held = await tx.get(holdRef);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (slot.exists) return false;
      if (held.exists && held['owner'] != me && (held['expiresAt'] as int) > now) return false;
      tx.set(holdRef, {'owner': me, 'holderUid': _uid, 'clinicianId': clinicianId, 'date': date, 'minute': minute, 'expiresAt': now + length.inMilliseconds});
      return true;
    });
  }

  @override
  void releaseHolds(String owner) {
    final me = _owner(owner);
    for (final e in _holds.entries.where((e) => e.value['owner'] == me).toList()) {
      final clinicId = e.key.split('|').first;
      // a hold taken before the person signed in belongs to their old anonymous session; it simply expires
      _clinicDoc(clinicId).collection('holds').doc(e.key.split('|').last).delete().catchError((Object e) => debugPrint('hold not released: $e'));
    }
  }

  // ---------------------------------------------------------------- phone codes
  static String _e164(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    return d.length == 10 ? '+1$d' : '+$d';
  }

  final _unconfirmed = <String, int>{};

  @override
  Future<void> sendVerificationCode(String phone) async {
    final p = _e164(phone);
    if ((_unconfirmed[p] ?? 0) >= 2) throw const RateLimitException();
    _unconfirmed[p] = (_unconfirmed[p] ?? 0) + 1;
    await _startPhoneSignIn(p, 'verification');
  }

  @override
  Future<bool> verifyCode(String phone, String code) => _confirmPhone(code);

  @override
  Future<void> sendSignInCode(String phoneOrEmail) => _startPhoneSignIn(_e164(phoneOrEmail), 'sign-in');

  @override
  Future<bool> signIn(String phoneOrEmail, String code) => _confirmPhone(code);

  /// Firebase phone sign-in. On a real project this is signInWithPhoneNumber (with reCAPTCHA
  /// on the web). On the emulator, web phone sign-in still asks Google's real reCAPTCHA
  /// service, so instead the code is requested from the emulator directly, read back from it
  /// and shown in [inbox] (no text is sent), and the app signs in with the standard phone
  /// credential built from that request.
  String? _emulatorSession;
  String get _authBase => 'http://$_emulatorHost:9099/identitytoolkit.googleapis.com/v1';

  Future<void> _startPhoneSignIn(String phone, String purpose) async {
    if (_emulatorHost == null) {
      _pendingPhone = await _auth.signInWithPhoneNumber(phone);
      return;
    }
    final sent = await http.post(Uri.parse('$_authBase/accounts:sendVerificationCode?key=demo-key'),
        headers: const {'Content-Type': 'application/json'}, body: jsonEncode({'phoneNumber': phone, 'recaptchaToken': 'emulator'}));
    if (sent.statusCode != 200) throw StateError('Auth emulator refused the code request: ${sent.body}');
    _emulatorSession = jsonDecode(sent.body)['sessionInfo'];
    final res = await http.get(Uri.parse('http://$_emulatorHost:9099/emulator/v1/projects/demo-clinicflow/verificationCodes'));
    final codes = (jsonDecode(res.body)['verificationCodes'] as List).where((c) => c['phoneNumber'] == phone).toList();
    if (codes.isNotEmpty) inbox.value = 'ClinicFlow: ${codes.last['code']} is your $purpose code. Don\'t share it.';
  }

  Future<bool> _confirmPhone(String code) async {
    if (_emulatorHost != null) {
      final session = _emulatorSession;
      if (session == null) return false;
      try {
        await _auth.signInWithCredential(PhoneAuthProvider.credential(verificationId: session, smsCode: code.trim()));
      } on FirebaseAuthException catch (e) {
        debugPrint('emulator phone sign-in failed: ${e.code}');
        return false;
      }
      _emulatorSession = null;
      return true;
    }
    final pending = _pendingPhone;
    if (pending == null) return false;
    try {
      await pending.confirm(code.trim());
      _pendingPhone = null;
      return true;
    } on FirebaseAuthException {
      return false;
    }
  }

  @override
  bool get signedIn => _auth.currentUser != null && !_auth.currentUser!.isAnonymous;

  /// Face ID unlocks a sign-in saved on the phone; the web test has none to unlock.
  @override
  Future<bool> signInWithDevice() async => signedIn;

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    await _auth.signInAnonymously();
  }

  // ---------------------------------------------------------------- booking
  @override
  Future<BookingResult> book(BookingRequest r) async {
    if (!signedIn) return const BookingResult(BookingOutcome.holdExpired);
    if (slotState(r.clinicianId, r.date, r.minute, viewer: r.owner) == SlotState.blocked) return const BookingResult(BookingOutcome.slotTaken);
    final c = _clinicDoc(r.clinicId), key = _slotKey(r.clinicianId, r.date, r.minute), me = _owner(r.owner);
    final slotRef = c.collection('slots').doc(key), holdRef = c.collection('holds').doc(key), apptRef = c.collection('appointments').doc();
    final digits = r.phone.replaceAll(RegExp(r'\D'), '');
    final data = {
      'clinicianId': r.clinicianId,
      'serviceId': r.serviceId,
      'patientName': r.patientName,
      'patientUid': _uid,
      'minute': r.minute,
      'status': ApptStatus.confirmed.name, // the phone code is the confirmation
      'formsDone': false,
      'phoneLast4': digits.length >= 4 ? digits.substring(digits.length - 4) : null,
      'bookedByGuardian': r.bookedByGuardian,
      'date': r.date,
    };
    // the double-booking guard: the slot document can only be created once
    final outcome = await _db.runTransaction<BookingOutcome>((tx) async {
      final slot = await tx.get(slotRef), held = await tx.get(holdRef);
      if (slot.exists) return BookingOutcome.slotTaken;
      if (!held.exists || held['owner'] != me || (held['expiresAt'] as int) <= DateTime.now().millisecondsSinceEpoch) return BookingOutcome.holdExpired;
      tx.set(slotRef, {'appointmentId': apptRef.id, 'clinicianId': r.clinicianId, 'date': r.date, 'minute': r.minute});
      tx.set(apptRef, data);
      tx.delete(holdRef);
      return BookingOutcome.booked;
    });
    if (outcome != BookingOutcome.booked) return BookingResult(outcome);
    _unconfirmed.remove(_e164(r.phone));
    _apptClinic[apptRef.id] = r.clinicId;
    // a first booking for themselves fills in the new patient's profile
    if (!r.bookedByGuardian && (profile?.name ?? '').isEmpty) {
      await saveProfile(name: r.patientName, email: r.email).catchError((Object e) => debugPrint('profile not saved: $e'));
    }
    if (_patient['homeClinic'] == null) {
      await _me.set({'homeClinic': r.clinicId}, SetOptions(merge: true)).catchError((Object e) => debugPrint('home clinic not saved: $e'));
    }
    final cl = clinic(r.clinicId);
    await _notify('Booked${r.bookedByGuardian ? ' for ${r.patientName.split(' ').first}' : ''}: ${service(r.serviceId).short}, ${shortDate(r.date)}, ${formatTime(r.minute)} with ${clinician(r.clinicianId).short}${cl.isHome ? '' : ' at ${cl.name}'}.',
        'text and email', NoticeKind.update);
    final appt = Appointment(
      id: apptRef.id,
      clinicId: r.clinicId,
      clinicianId: r.clinicianId,
      serviceId: r.serviceId,
      patientName: r.patientName,
      date: r.date,
      minute: r.minute,
      status: ApptStatus.confirmed,
      mine: true,
      bookedByGuardian: r.bookedByGuardian,
    );
    return BookingResult(BookingOutcome.booked, appt);
  }

  DocumentReference<Map<String, dynamic>> _apptRef(String id) => _clinicDoc(_apptClinic[id]!).collection('appointments').doc(id);
  Appointment _appt(String id) => _mine.firstWhere((a) => a.id == id);

  /// "Thu Oct 29, 9:00 am".
  String _when(String date, int minute) => '${shortDate(date)}, ${formatTime(minute)}';

  @override
  Future<BookingResult> reschedule(String id, {required String clinicianId, required String date, required int minute, required String owner}) async {
    final a = _appt(id), c = _clinicDoc(a.clinicId), me = _owner(owner);
    final newKey = _slotKey(clinicianId, date, minute), oldKey = _slotKey(a.clinicianId, a.date, a.minute);
    final from = _when(a.date, a.minute);
    final outcome = await _db.runTransaction<BookingOutcome>((tx) async {
      final slot = await tx.get(c.collection('slots').doc(newKey)), held = await tx.get(c.collection('holds').doc(newKey));
      if (slot.exists) return BookingOutcome.slotTaken;
      if (!held.exists || held['owner'] != me || (held['expiresAt'] as int) <= DateTime.now().millisecondsSinceEpoch) return BookingOutcome.holdExpired;
      tx.set(c.collection('slots').doc(newKey), {'appointmentId': id, 'clinicianId': clinicianId, 'date': date, 'minute': minute});
      tx.delete(c.collection('slots').doc(oldKey));
      tx.delete(c.collection('holds').doc(newKey));
      tx.update(_apptRef(id), {'clinicianId': clinicianId, 'date': date, 'minute': minute});
      return BookingOutcome.booked;
    });
    if (outcome != BookingOutcome.booked) return BookingResult(outcome);
    await _notify('Moved: your visit is now ${_when(date, minute)} with ${clinician(clinicianId).short} (was $from).', 'push and text', NoticeKind.update);
    return BookingResult(outcome, a
      ..clinicianId = clinicianId
      ..date = date
      ..minute = minute);
  }

  // ---------------------------------------------------------------- my visits
  @override
  List<Appointment> myAppointments() => List.unmodifiable(_mine);

  @override
  Future<void> confirmVisit(String id) async {
    if (_appt(id).status == ApptStatus.booked) await _apptRef(id).update({'status': ApptStatus.confirmed.name});
  }

  @override
  bool lateCancellation(String id) => clock.hoursUntil(_appt(id).date, _appt(id).minute) < cancelWindowHours;

  @override
  Future<void> cancelVisit(String id) async {
    final a = _appt(id);
    final batch = _db.batch()
      ..update(_apptRef(id), {'status': ApptStatus.cancelled.name})
      ..delete(_clinicDoc(a.clinicId).collection('slots').doc(_slotKey(a.clinicianId, a.date, a.minute))); // the time is free again
    await batch.commit();
    await _notify('Your visit on ${_when(a.date, a.minute)} is cancelled. The time was offered to the waitlist.', 'push', NoticeKind.notice);
  }

  @override
  Future<Appointment> checkIn(String id) async {
    final a = _appt(id), c = _clinicDoc(a.clinicId);
    // ticket numbers start over each day
    final counterRef = c.collection('counters').doc('tickets-${a.date}');
    final ticket = await _db.runTransaction<String>((tx) async {
      final counter = await tx.get(counterRef);
      final n = (counter.data()?['next'] as int?) ?? 1;
      final t = 'A-$n';
      tx.set(counterRef, {'next': n + 1});
      tx.update(_apptRef(id), {'status': ApptStatus.checkedIn.name, 'ticket': t, 'checkedInAt': nowMinute});
      tx.set(c.collection('queue').doc('${a.date}_$t'), {'ticket': t, 'n': n, 'date': a.date, 'clinicianId': a.clinicianId, 'status': ApptStatus.checkedIn.name});
      return t;
    });
    await _notify("You're checked in. Ticket $ticket.", 'push', NoticeKind.update);
    return a
      ..ticket = ticket
      ..status = ApptStatus.checkedIn;
  }

  @override
  int peopleAhead(String id) {
    final a = _appt(id), mine = int.tryParse((a.ticket ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0;
    return _queue
        .where((q) => q['clinicId'] == a.clinicId && q['date'] == a.date && q['clinicianId'] == a.clinicianId && q['status'] == ApptStatus.waiting.name && (q['n'] as int) < mine)
        .length;
  }

  @override
  Future<void> submitIntake(String id, IntakeAnswers answers) =>
      _apptRef(id).update({'formsDone': true, 'intake': {'visitType': answers.visitType, 'note': answers.note, 'contactByText': answers.contactByText}});

  // ---------------------------------------------------------------- profile
  @override
  PatientProfile? get profile => signedIn
      ? PatientProfile(name: _patient['name'] ?? '', phone: _auth.currentUser?.phoneNumber ?? '', email: _patient['email'] ?? '')
      : null;

  @override
  Future<void> saveProfile({required String name, required String email}) => _me.set({'name': name.trim(), 'email': email.trim()}, SetOptions(merge: true));

  /// Recorded on the patient's record; answering it (by email, within 30 days) comes with Cloud Functions.
  @override
  Future<void> requestMyData(String kind) => _me.set({
        'dataRequests': FieldValue.arrayUnion([
          {'kind': kind, 'at': DateTime.now().millisecondsSinceEpoch},
        ]),
      }, SetOptions(merge: true));

  @override
  bool get smsConsent => _patient['smsConsent'] ?? false;
  @override
  String get smsConsentChangedOn => _patient['consentDate'] ?? '';
  @override
  Future<void> setSmsConsent(bool on) => _me.set({'smsConsent': on, 'consentDate': today}, SetOptions(merge: true));

  @override
  List<FamilyMember> family() => List.unmodifiable(_family);

  @override
  Future<FamilyMember> addFamilyMember({required String name, required String relationship, DateTime? born}) async {
    final ref = await _me.collection('family').add({'name': name, 'relationship': relationship, 'born': born?.toIso8601String().substring(0, 10)});
    return FamilyMember(id: ref.id, name: name, relationship: relationship, born: born);
  }

  // ---------------------------------------------------------------- waitlist
  @override
  WaitlistRequest? myWaitlist() {
    final w = _patient['waitlist'] as Map<String, dynamic>?;
    if (w == null) return null;
    return WaitlistRequest(
      days: Set<String>.from(w['days']),
      parts: {for (final p in w['parts']) DayPart.values.byName(p)},
      clinicianId: w['clinicianId'],
    );
  }

  /// Saves the request on the patient's record and on the clinic's waitlist, where the front
  /// desk sees it and can offer a freed time. Automatic offers come with Cloud Functions.
  @override
  Future<void> joinWaitlist(WaitlistRequest r) async {
    final w = {'days': r.days.toList(), 'parts': [for (final p in r.parts) p.name], 'clinicianId': r.clinicianId, 'joinedAt': DateTime.now().millisecondsSinceEpoch};
    final visit = upcomingVisits().where((a) => a.status.upcoming).firstOrNull;
    final batch = _db.batch()..set(_me, {'waitlist': w}, SetOptions(merge: true));
    if (visit != null) {
      batch.set(_clinicDoc(visit.clinicId).collection('waitlist').doc(_uid), {
        ...w,
        'uid': _uid,
        'name': visit.patientName,
        'appointmentId': visit.id,
        'serviceId': visit.serviceId,
        'date': visit.date,
        'minute': visit.minute,
        'priority': false,
      });
    }
    await batch.commit();
  }

  Future<void> _leaveClinicWaitlist(String clinicId) =>
      _clinicDoc(clinicId).collection('waitlist').doc(_uid).delete().catchError((Object e) => debugPrint('waitlist entry not removed: $e'));

  @override
  WaitlistOffer? pendingOffer() => _offers.where((o) => o.$2.live).map((o) => o.$2).firstOrNull;

  @override
  Future<void> acceptOffer() async {
    final entry = _offers.where((o) => o.$2.live).firstOrNull;
    if (entry == null) return;
    final (offerId, o) = entry;
    final a = _appt(o.appointmentId), c = _clinicDoc(a.clinicId), from = _when(a.date, a.minute);
    final newSlot = c.collection('slots').doc(_slotKey(o.clinicianId, o.date, o.minute));
    await _db.runTransaction((tx) async {
      final slot = await tx.get(newSlot);
      if (slot.exists) return;
      tx.set(newSlot, {'appointmentId': a.id, 'clinicianId': o.clinicianId, 'date': o.date, 'minute': o.minute});
      tx.delete(c.collection('slots').doc(_slotKey(a.clinicianId, a.date, a.minute)));
      tx.update(_apptRef(a.id), {'clinicianId': o.clinicianId, 'date': o.date, 'minute': o.minute});
      tx.delete(_me.collection('offers').doc(offerId));
    });
    await _me.update({'waitlist': FieldValue.delete()});
    await _leaveClinicWaitlist(a.clinicId);
    await _notify('Moved: your visit is now ${_when(o.date, o.minute)} with ${clinician(o.clinicianId).short} (was $from).', 'push and text', NoticeKind.update);
  }

  @override
  Future<void> declineOffer() async {
    final entry = _offers.where((o) => o.$2.live).firstOrNull;
    if (entry == null) return;
    await _me.collection('offers').doc(entry.$1).delete();
    // still on the waitlist, but this offer is no longer pending at the front desk
    final visit = _mine.where((a) => a.id == entry.$2.appointmentId).firstOrNull;
    if (visit != null) {
      await _clinicDoc(visit.clinicId).collection('waitlist').doc(_uid).update({'offer': FieldValue.delete(), 'passed': FieldValue.increment(1)}).catchError((Object e) => debugPrint('$e'));
    }
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
    final batch = _db.batch();
    for (final v in _history.where((v) => v.owing > 0)) {
      batch.update(_me.collection('history').doc(_historyIds[v]), {'owing': 0});
    }
    await batch.commit();
    await _notify('Paid \$${paid.toStringAsFixed(2)}. Your receipt was emailed.', 'email', NoticeKind.update);
    return paid;
  }
}
