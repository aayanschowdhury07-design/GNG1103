import 'dart:async';
import 'dart:math' as math;

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'clinic_desk.dart';
import 'clinic_review.dart';
import 'firebase_connect.dart';

/// The eight setup steps, in order.
const setupSteps = [
  'Clinic profile & branding',
  'Services & durations',
  'Clinicians & hours',
  'Existing appointments',
  'Booking link & QR code',
  'Reminder & waitlist rules',
  'Invite staff, set roles',
  'Directory listing',
];

const staffRoles = {'admin': 'Admin', 'frontdesk': 'Front desk', 'clinician': 'Clinician', 'support': 'Support'};
const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class SetupService {
  const SetupService({required this.id, required this.name, this.nameFr = '', required this.minutes, this.online = true, this.who = '', this.clinicianIds = const [], this.order = 0});
  final String id, name, nameFr, who;
  final int minutes, order;
  final bool online;
  final List<String> clinicianIds;
}

class SetupClinician {
  const SetupClinician({required this.id, required this.name, required this.role, required this.days, required this.start, required this.end, this.short = ''});
  final String id, name, role;

  /// "Dr. Osei": for calendar columns and staff lists.
  final String short;
  final List<String> days;

  /// Working hours, in minutes after midnight.
  final int start, end;
}

class SetupInvite {
  const SetupInvite({required this.id, required this.name, required this.email, required this.role, this.clinicId = '', this.clinicName = '', this.clinicianId});
  final String id, name, email, role, clinicId, clinicName;
  final String? clinicianId;

  static SetupInvite fromDoc(DocumentSnapshot<Map<String, dynamic>> d) => SetupInvite(
        id: d.id,
        name: d.data()?['name'] ?? '',
        email: d.data()?['email'] ?? d.id,
        role: d.data()?['role'] ?? 'support',
        clinicId: d.reference.parent.parent!.id,
        clinicName: d.data()?['clinicName'] ?? '',
        clinicianId: d.data()?['clinicianId'],
      );
}

/// The admin website's side of Firebase: staff accounts, creating a clinic and saving each
/// setup step. Everything is written to clinics/{clinic} as the admin goes, so setup can be
/// left and resumed, and the security rules only let this clinic's admins write it.
class ClinicSetup extends ChangeNotifier {
  ClinicSetup._(this._db, this._auth, this.clock);

  static Future<ClinicSetup> startProject(FirebaseOptions options, {ClinicClock? clock}) async {
    final (db, auth) = await connectFirebase(options: options);
    return ClinicSetup._(db, auth, clock ?? ClinicClock.real()).._listenAuth();
  }

  /// [clock] can start at the seeded sample morning, so the sample day plays out at any hour.
  static Future<ClinicSetup> startEmulators({String host = 'localhost', ClinicClock? clock}) async {
    final (db, auth) = await connectFirebase(emulatorHost: host);
    return ClinicSetup._(db, auth, clock ?? ClinicClock.real()).._listenAuth();
  }

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ClinicClock clock;
  final _subs = <StreamSubscription<dynamic>>[];
  StreamSubscription<User?>? _authSub;

  bool loading = true;
  User? get user => _auth.currentUser;
  bool get signedIn => user != null && !user!.isAnonymous;
  bool get emailVerified => user?.emailVerified ?? false;

  /// The clinic this person works at (null until they create or join one).
  String? clinicId;
  Map<String, dynamic> clinic = const {};
  List<SetupService> services = const [];
  List<SetupClinician> clinicians = const [];
  List<SetupInvite> invites = const [];

  /// Their own staff record at that clinic, and the clinic's day for their role.
  StaffMember? me;
  ClinicDesk? desk;

  /// Clinics that invited this email address, for someone without a clinic yet.
  List<SetupInvite> pendingInvites = const [];

  /// Set for the ClinicFlow team, who review new clinics instead of running one.
  ClinicReview? review;
  bool get platformAdmin => review != null;

  DocumentReference<Map<String, dynamic>> get _clinicRef => _db.collection('clinics').doc(clinicId);

  void _listenAuth() {
    _authSub = _auth.authStateChanges().listen((u) async {
      loading = true;
      notifyListeners();
      await _findClinic(u);
      loading = false;
      notifyListeners();
    });
  }

  Future<void> _findClinic(User? u) async {
    _stopClinic();
    clinicId = null;
    pendingInvites = const [];
    review?.dispose();
    review = null;
    if (u == null || u.isAnonymous) return;
    // the ClinicFlow team (added from the Firebase console) reviews clinics
    if (u.emailVerified) {
      try {
        if ((await _db.collection('platformAdmins').doc(u.uid).get()).exists) {
          review = ClinicReview(_db, u);
          return;
        }
      } on FirebaseException catch (e) {
        debugPrint('team check: ${e.code}'); // not on the team, or the rules aren't deployed yet
      }
    }
    // the clinic this person is staff at
    final mine = await _db.collectionGroup('staff').where('uid', isEqualTo: u.uid).limit(1).get();
    if (mine.docs.isNotEmpty) return _openClinic(mine.docs.first.reference.parent.parent!.id);
    // otherwise: has a clinic invited them? Invitations are matched on a verified email only,
    // so nobody can claim someone else's invitation by signing up with their address
    if (u.emailVerified && u.email != null) {
      final q = await _db.collectionGroup('invites').where('email', isEqualTo: u.email!.toLowerCase()).get();
      pendingInvites = [for (final d in q.docs) SetupInvite.fromDoc(d)];
    }
  }

  /// Sends the "verify your email" link (Firebase Authentication sends it; no server code needed).
  Future<void> sendVerification() => user!.sendEmailVerification();

  /// After they've clicked the link: refresh the account and look for invitations again.
  Future<void> checkVerified() async {
    await user!.reload();
    await user!.getIdToken(true); // the rules read email_verified from a fresh token
    await _findClinic(user);
    notifyListeners();
  }

  /// Joins the clinic that invited them, in the role the admin chose.
  Future<void> acceptInvite(SetupInvite i) async {
    final u = user!, ref = _db.collection('clinics').doc(i.clinicId);
    final batch = _db.batch()
      ..set(ref.collection('staff').doc(u.uid), {
        'uid': u.uid,
        'name': (u.displayName ?? '').isEmpty ? i.name : u.displayName,
        'email': u.email!.toLowerCase(),
        'role': i.role,
        'clinicianId': i.clinicianId,
        'clinicName': i.clinicName,
      })
      ..delete(ref.collection('invites').doc(i.id));
    await batch.commit();
    pendingInvites = const [];
    _openClinic(i.clinicId);
    notifyListeners();
  }

  void _openClinic(String id) {
    clinicId = id;
    _subs
      ..add(_clinicRef.snapshots().listen((d) {
        clinic = d.data() ?? const {};
        notifyListeners();
      }))
      ..add(_clinicRef.collection('staff').doc(user!.uid).snapshots().listen((d) {
        final next = d.exists ? StaffMember.fromDoc(d.id, d.data()!) : null;
        // a role change changes what this person may read, so the day restarts with it
        if (next?.role != me?.role || next?.clinicianId != me?.clinicianId) {
          desk?.dispose();
          desk = next == null ? null : ClinicDesk(_db, id, next, clock: clock);
        }
        me = next;
        notifyListeners();
      }))
      ..add(_clinicRef.collection('services').orderBy('order').snapshots().listen((q) {
        services = [
          for (final d in q.docs)
            SetupService(
              id: d.id,
              name: d.data()['name'] ?? '',
              nameFr: d.data()['nameFr'] ?? '',
              minutes: d.data()['minutes'] ?? 30,
              online: d.data()['online'] ?? true,
              who: d.data()['who'] ?? '',
              clinicianIds: List<String>.from(d.data()['clinicianIds'] ?? const []),
              order: d.data()['order'] ?? 0,
            ),
        ];
        notifyListeners();
      }))
      // in the order they were added; clinicians from before setup recorded that sort first
      ..add(_clinicRef.collection('clinicians').snapshots().listen((q) {
        final docs = [...q.docs]..sort((a, b) => ((a.data()['addedAt'] as int?) ?? 0).compareTo((b.data()['addedAt'] as int?) ?? 0));
        clinicians = [
          for (final d in docs)
            SetupClinician(
              id: d.id,
              name: d.data()['name'] ?? '',
              role: d.data()['role'] ?? '',
              days: List<String>.from(d.data()['days'] ?? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']),
              start: d.data()['start'] ?? 9 * 60,
              end: d.data()['end'] ?? 17 * 60,
              short: d.data()['short'] ?? d.data()['name'] ?? '',
            ),
        ];
        notifyListeners();
      }));
    // only admins can read the invitations
    _subs.add(_clinicRef.collection('invites').snapshots().listen((q) {
      invites = [for (final d in q.docs) SetupInvite.fromDoc(d)];
      notifyListeners();
    }, onError: (Object _) {}));
  }

  void _stopClinic() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    desk?.dispose();
    desk = null;
    me = null;
    clinic = const {};
    services = const [];
    clinicians = const [];
    invites = const [];
  }

  @override
  void dispose() {
    _stopClinic();
    review?.dispose();
    _authSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- staff accounts
  /// Creates the account and sends the "verify your email" link straight away: a clinic can
  /// only be created, or an invitation used, with a verified address.
  Future<void> signUp({required String name, required String email, required String password}) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    await cred.user!.updateDisplayName(name.trim());
    await cred.user!.sendEmailVerification().catchError((Object e) => debugPrint('verification email not sent: $e'));
  }

  Future<void> signIn(String email, String password) => _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email.trim());
  Future<void> signOut() => _auth.signOut();

  // ---------------------------------------------------------------- setup
  /// The ClinicFlow review: 'draft' while setting up, then 'pending', 'approved' or 'rejected'.
  String get approval => clinic['approval'] ?? 'draft';
  bool get approved => approval == 'approved';

  /// Why the clinic wasn't approved, from the ClinicFlow team.
  String get approvalNote => clinic['approvalNote'] ?? '';

  /// After fixing what the review asked for: back in the queue.
  Future<void> resubmit() => _clinicRef.update({'approval': 'pending', 'submittedAt': DateTime.now().millisecondsSinceEpoch});

  int get step => (clinic['setup']?['step'] as int?) ?? 1;
  List<int> get doneSteps => List<int>.from(clinic['setup']?['done'] ?? const []);
  bool get finished => clinic['setup']?['finishedAt'] != null;
  DateTime? get startedAt => clinic['setup']?['startedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(clinic['setup']['startedAt']);
  DateTime? get finishedAt => clinic['setup']?['finishedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(clinic['setup']['finishedAt']);

  /// Creates the clinic with this person as its first admin, in one write (see firestore.rules).
  Future<void> createClinic(String name) async {
    final u = user!;
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    final id = '${slug.isEmpty ? 'clinic' : slug}-${List.generate(4, (_) => 'abcdefghjkmnpqrstuvwxyz23456789'[math.Random().nextInt(31)]).join()}';
    final ref = _db.collection('clinics').doc(id);
    final batch = _db.batch()
      ..set(ref, {
        'name': name.trim(),
        'initials': _initials(name),
        'ownerUid': u.uid,
        // hidden from patients until setup is finished and ClinicFlow approves the clinic
        'ready': false,
        'approval': 'draft',
        'listed': true,
        'accepting': true,
        'address': '',
        'city': '',
        'phone': '',
        'kind': '',
        'lat': 43.6532,
        'lng': -79.3832,
        'brand': 'blue',
        'languages': ['en', 'fr'],
        'rules': {'cancelWindowHours': 24, 'offerHoldMinutes': 15, 'cutoffMinutes': 60, 'remind48': true, 'remind24': true},
        'existing': 'fresh',
        'setup': {'step': 1, 'done': <int>[], 'startedAt': DateTime.now().millisecondsSinceEpoch, 'finishedAt': null},
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(ref.collection('staff').doc(u.uid), {'uid': u.uid, 'name': u.displayName ?? '', 'email': u.email ?? '', 'role': 'admin', 'clinicName': name.trim()});
    await batch.commit();
    _openClinic(id);
    notifyListeners();
  }

  static String _initials(String name) => name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

  Future<void> goToStep(int n) => _clinicRef.update({'setup.step': n});

  /// Marks [n] done and moves on. The last step finishes setup and submits the clinic for
  /// review; patients find and book it once ClinicFlow approves it.
  Future<void> completeStep(int n) async {
    final done = {...doneSteps, n}.toList()..sort();
    if (n < setupSteps.length) {
      await _clinicRef.update({'setup.done': done, 'setup.step': n + 1});
    } else {
      await _clinicRef.update({
        'setup.done': done,
        'setup.finishedAt': clinic['setup']?['finishedAt'] ?? DateTime.now().millisecondsSinceEpoch,
        'ready': true,
        if (approval == 'draft') ...{'approval': 'pending', 'submittedAt': DateTime.now().millisecondsSinceEpoch},
      });
    }
  }

  Future<void> restartTimer() => _clinicRef.update({'setup.startedAt': DateTime.now().millisecondsSinceEpoch, 'setup.finishedAt': null});

  /// Step 1. [lat]/[lng] place the clinic on the patients' map.
  Future<void> saveProfile({
    required String name,
    required String address,
    required String city,
    required String phone,
    required String kind,
    required String brand,
    required List<String> languages,
    required double lat,
    required double lng,
  }) =>
      _clinicRef.update({
        'name': name.trim(),
        'initials': _initials(name),
        'address': address.trim(),
        'city': city.trim(),
        'phone': phone.trim(),
        'kind': kind.trim(),
        'brand': brand,
        'languages': languages,
        'lat': lat,
        'lng': lng,
      });

  // step 2
  Future<void> addService({required String name, String nameFr = '', required int minutes, required bool online, String who = ''}) =>
      _clinicRef.collection('services').add({
        'name': name.trim(),
        'nameFr': nameFr.trim(),
        // a short label for staff lists: the part before " · " if there is one
        'short': name.split('·').first.trim(),
        'minutes': minutes,
        'online': online,
        'who': who.trim(),
        'clinicianIds': <String>[],
        'order': services.length,
      });

  Future<void> setServiceOnline(String id, bool online) => _clinicRef.collection('services').doc(id).update({'online': online});
  Future<void> removeService(String id) => _clinicRef.collection('services').doc(id).delete();

  // step 3
  Future<void> addClinician({required String name, required String role, required List<String> days, required int start, required int end, required List<String> serviceIds}) async {
    final ref = _clinicRef.collection('clinicians').doc();
    final batch = _db.batch()
      ..set(ref, {
        'name': name.trim(),
        'short': _shortName(name),
        'role': role.trim(),
        'days': days,
        'start': start,
        'end': end,
        'addedAt': DateTime.now().millisecondsSinceEpoch,
      });
    // which services this clinician offers
    for (final s in services) {
      if (serviceIds.contains(s.id)) batch.update(_clinicRef.collection('services').doc(s.id), {'clinicianIds': FieldValue.arrayUnion([ref.id])});
    }
    await batch.commit();
  }

  Future<void> updateClinicianHours(String id, {required List<String> days, required int start, required int end}) =>
      _clinicRef.collection('clinicians').doc(id).update({'days': days, 'start': start, 'end': end});

  Future<void> removeClinician(String id) async {
    final batch = _db.batch()..delete(_clinicRef.collection('clinicians').doc(id));
    for (final s in services.where((s) => s.clinicianIds.contains(id))) {
      batch.update(_clinicRef.collection('services').doc(s.id), {'clinicianIds': FieldValue.arrayRemove([id])});
    }
    await batch.commit();
  }

  /// "Dr. Kwame Osei" -> "Dr. Osei"; "Mei Lam, PT" -> "M. Lam".
  static String _shortName(String name) {
    final clean = name.split(',').first.trim();
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length < 2) return clean;
    if (parts.first == 'Dr.' || parts.first == 'Dr') return 'Dr. ${parts.last}';
    return '${parts.first[0]}. ${parts.last}';
  }

  // step 4
  Future<void> setExisting(String choice) => _clinicRef.update({'existing': choice});

  // step 6
  Future<void> setRule(String key, Object value) => _clinicRef.update({'rules.$key': value});

  // step 7
  /// [clinicianId] links a clinician-role account to the clinician it is.
  Future<void> invite({required String name, required String email, required String role, String? clinicianId}) =>
      _clinicRef.collection('invites').doc(email.trim().toLowerCase()).set({
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'role': role,
        'clinicianId': role == 'clinician' ? clinicianId : null,
        'clinicName': clinic['name'] ?? '',
        'invitedAt': DateTime.now().millisecondsSinceEpoch,
        'invitedBy': user?.uid,
      });

  Future<void> removeInvite(String id) => _clinicRef.collection('invites').doc(id).delete();

  // step 8
  Future<void> setListed(bool listed) => _clinicRef.update({'listed': listed});
}
