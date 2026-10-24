import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// A clinic as the ClinicFlow team sees it in the review queue.
class ReviewClinic {
  const ReviewClinic(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  String get name => data['name'] ?? '';
  String get address => [data['address'], data['city']].where((x) => x is String && x.isNotEmpty).join(', ');
  String get phone => data['phone'] ?? '';
  String get kind => data['kind'] ?? '';
  String get ownerUid => data['ownerUid'] ?? '';
  double? get lat => (data['lat'] as num?)?.toDouble();
  double? get lng => (data['lng'] as num?)?.toDouble();
  List<String> get languages => List<String>.from(data['languages'] ?? const []);

  /// 'draft' (still setting up), 'pending', 'approved' or 'rejected'.
  String get approval => data['approval'] ?? 'draft';
  String get note => data['approvalNote'] ?? '';
  bool get listed => data['listed'] != false;
  DateTime? get submittedAt => data['submittedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(data['submittedAt']);
  DateTime? get reviewedAt => data['reviewedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(data['reviewedAt']);
}

/// What the review needs beyond the clinic's public profile: who set it up, and what it offers.
class ReviewDetails {
  const ReviewDetails({required this.ownerName, required this.ownerEmail, required this.services, required this.clinicians});
  final String ownerName, ownerEmail;
  final List<String> services, clinicians;
}

/// The ClinicFlow team's review of new clinics. A clinic that finished setup waits here as
/// 'pending'; approving it lets patients find and book it, rejecting it sends it back with a
/// note. The security rules let only the team (platformAdmins/{uid}) decide, and only these fields.
class ClinicReview extends ChangeNotifier {
  ClinicReview(this._db, this._user) {
    _sub = _db.collection('clinics').snapshots().listen((q) {
      clinics = [for (final d in q.docs) ReviewClinic(d.id, d.data())]
        ..sort((a, b) => (b.submittedAt ?? DateTime(0)).compareTo(a.submittedAt ?? DateTime(0)));
      notifyListeners();
    }, onError: (Object e) => debugPrint('review: $e'));
  }

  final FirebaseFirestore _db;
  final User _user;
  StreamSubscription<dynamic>? _sub;
  List<ReviewClinic> clinics = const [];
  final _details = <String, Future<ReviewDetails>>{};

  String get email => _user.email ?? '';

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<ReviewDetails> details(ReviewClinic c) => _details[c.id] ??= _load(c);

  Future<ReviewDetails> _load(ReviewClinic c) async {
    final ref = _db.collection('clinics').doc(c.id);
    final owner = c.ownerUid.isEmpty ? null : await ref.collection('staff').doc(c.ownerUid).get();
    final services = await ref.collection('services').get(), clinicians = await ref.collection('clinicians').get();
    return ReviewDetails(
      ownerName: owner?.data()?['name'] ?? '',
      ownerEmail: owner?.data()?['email'] ?? '',
      services: [for (final d in services.docs) '${d.data()['name']} · ${d.data()['minutes']} min'],
      clinicians: [for (final d in clinicians.docs) '${d.data()['name']}, ${d.data()['role']}'],
    );
  }

  Future<void> approve(ReviewClinic c) => _decide(c, 'approved', '', 'Approved: patients can now find and book ${c.name}.');

  /// [note] tells the clinic what to fix; they see it in their staff website.
  Future<void> reject(ReviewClinic c, String note) => _decide(c, 'rejected', note.trim(), 'Not approved yet: ${note.trim()}');

  Future<void> _decide(ReviewClinic c, String to, String note, String message) async {
    final ref = _db.collection('clinics').doc(c.id);
    final owner = await details(c);
    final batch = _db.batch()
      ..update(ref, {
        'approval': to,
        'approvalNote': note.isEmpty ? FieldValue.delete() : note,
        'reviewedAt': DateTime.now().millisecondsSinceEpoch,
        'reviewedBy': _user.uid,
      })
      // the owner hears by email once Cloud Functions send the outbox
      ..set(ref.collection('outbox').doc(), {
        'at': FieldValue.serverTimestamp(),
        'by': _user.uid,
        'to': owner.ownerEmail.isEmpty ? c.name : owner.ownerEmail,
        'message': 'ClinicFlow review · $message',
        'channel': 'Email',
        'status': 'queued',
      })
      ..set(ref.collection('audit').doc(), {
        'at': FieldValue.serverTimestamp(),
        'actorUid': _user.uid,
        'actor': 'ClinicFlow team ($email)',
        'action': 'clinic.$to',
        'record': 'CLINIC',
        'detail': note.isEmpty ? to : note,
      });
    await batch.commit();
  }
}
