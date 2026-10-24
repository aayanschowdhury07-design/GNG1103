import 'dart:async';

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'clinic_setup.dart';

/// A staff member's record: clinics/{clinic}/staff/{uid}. A clinician-role account is linked
/// to the clinician it is, so it sees only its own patients.
class StaffMember {
  const StaffMember({required this.uid, required this.name, required this.email, required this.role, this.clinicianId});
  final String uid, name, email, role;
  final String? clinicianId;

  bool get isAdmin => role == 'admin';

  /// Admins and the front desk run the day: booking, check-in, waitlist offers.
  bool get runsDay => role == 'admin' || role == 'frontdesk';

  /// Support staff can look at the queue but not change anything.
  bool get readOnly => role == 'support';

  static StaffMember fromDoc(String uid, Map<String, dynamic> d) => StaffMember(
        uid: uid,
        name: d['name'] ?? '',
        email: d['email'] ?? '',
        role: d['role'] ?? 'support',
        clinicianId: d['clinicianId'],
      );
}

/// An appointment as the clinic sees it, with the front desk's working fields.
class DeskAppt {
  const DeskAppt({
    required this.id,
    required this.clinicianId,
    required this.serviceId,
    required this.patientName,
    required this.minute,
    required this.date,
    required this.status,
    this.ticket,
    this.formsDone = false,
    this.phone,
    this.phoneLast4,
    this.patientUid,
    this.bookedBy,
    this.checkedInAt,
    this.waitingSince,
    this.calledAt,
    this.followUp,
    this.cancelledBy,
    this.intake,
  });
  final String id, clinicianId, serviceId, patientName, date;
  final int minute;
  final ApptStatus status;
  final String? ticket, phone, phoneLast4, patientUid, bookedBy, followUp, cancelledBy;
  final bool formsDone;

  /// Minutes after midnight on the sample clock.
  final int? checkedInAt, waitingSince, calledAt;
  final Map<String, dynamic>? intake;

  bool get active => status.active;

  static DeskAppt fromDoc(String id, Map<String, dynamic> d) => DeskAppt(
        id: id,
        clinicianId: d['clinicianId'] ?? '',
        serviceId: d['serviceId'] ?? '',
        patientName: d['patientName'] ?? 'Patient',
        minute: d['minute'] ?? 0,
        date: d['date'] ?? '',
        status: ApptStatus.values.asNameMap()[d['status']] ?? ApptStatus.booked,
        ticket: d['ticket'],
        formsDone: d['formsDone'] ?? false,
        phone: d['phone'],
        phoneLast4: d['phoneLast4'],
        patientUid: d['patientUid'],
        bookedBy: d['bookedBy'],
        checkedInAt: d['checkedInAt'],
        waitingSince: d['waitingSince'],
        calledAt: d['calledAt'],
        followUp: d['followUp'],
        cancelledBy: d['cancelledBy'],
        intake: d['intake'] as Map<String, dynamic>?,
      );
}

/// Unavailable time set by the clinic. [minutes] null is the whole day; [date] null is every day.
class DeskBlock {
  const DeskBlock({required this.id, required this.clinicianId, required this.type, this.minutes, this.date});
  final String id, clinicianId, type;
  final Set<int>? minutes;
  final String? date;
  bool covers(int minute, String day) => (date == null || date == day) && (minutes == null || minutes!.contains(minute));
}

/// Someone on the clinic's waitlist for an earlier time.
class WaitlistEntry {
  const WaitlistEntry({
    required this.uid,
    required this.name,
    required this.appointmentId,
    required this.serviceId,
    required this.date,
    required this.minute,
    required this.days,
    required this.parts,
    required this.joinedAt,
    this.clinicianId,
    this.priority = false,
    this.passed = 0,
    this.offer,
  });
  final String uid, name, appointmentId, serviceId;
  final String? clinicianId;

  /// When they're booked now; an offer has to be earlier than this.
  final String date;
  final int minute, passed;
  final Set<String> days;
  final Set<DayPart> parts;
  final DateTime joinedAt;
  final bool priority;

  /// The pending offer, if one was sent: {clinicianId, date, minute, expiresAt}.
  final Map<String, dynamic>? offer;
  bool get offerLive => offer != null && (offer!['expiresAt'] as int) > DateTime.now().millisecondsSinceEpoch;

  /// Could this person take [minute] on [date] with [clinicianId], and is it earlier than their visit?
  bool fits(String clinicianId, String date, int minute) =>
      days.contains(weekdayOf(date)) &&
      parts.contains(DayPart.of(minute)) &&
      (this.clinicianId == null || this.clinicianId == clinicianId) &&
      (date.compareTo(this.date) < 0 || (date == this.date && minute < this.minute));
}

/// A message waiting to be sent. Cloud Functions will deliver these and record the outcome.
class OutboxMessage {
  const OutboxMessage({required this.id, required this.to, required this.message, required this.channel, required this.status, this.at});
  final String id, to, message, channel, status;
  final DateTime? at;
}

class AuditEntry {
  const AuditEntry({required this.at, required this.actor, required this.action, required this.record, required this.detail});
  final DateTime? at;
  final String actor, action, record, detail;
}

/// A time freed by a cancellation, still ahead: open, offered to someone on the waitlist, or refilled.
class FreedSlot {
  const FreedSlot({required this.clinicianId, required this.date, required this.minute, required this.cancelled, this.refilledBy, this.offeredTo});
  final String clinicianId, date;
  final int minute;
  final DeskAppt cancelled;
  final String? refilledBy;
  final WaitlistEntry? offeredTo;
  bool get open => refilledBy == null && offeredTo == null;
}

/// The message templates staff can edit, with the prototype's wording as the starting text.
const messageTemplates = {
  'reminder24': ('Reminder, 24 h before',
      'Hi {first_name}, reminder: {service} with {clinician} tomorrow at {time}, {clinic}. Tap to confirm: {link}. Need to change it? Same link. Reply STOP to opt out.'),
  'cancelPatient': ('Cancellation, patient cancelled', 'Hi {first_name}, your {service} on {date} at {time} is cancelled. Book again any time: {link}. Reply STOP to opt out.'),
  'cancelClinic': ('Cancellation, clinic cancelled',
      "Hi {first_name}, we're sorry: we had to cancel your {service} with {clinician} on {date} at {time} ({reason}). You're first in line for a new time: {link}"),
  'missed': ('Missed visit follow-up', 'Hi {first_name}, we missed you at {time} today. No problem, life happens. Pick a new time that suits you: {link}. Reply STOP to opt out.'),
};

const defaultBlockTypes = [
  {'name': 'Break', 'scope': 'Each clinician'},
  {'name': 'Not in', 'scope': 'Each clinician'},
  {'name': 'Admin time', 'scope': 'Each clinician'},
  {'name': 'Vacation', 'scope': 'Each clinician'},
  {'name': 'Statutory holiday', 'scope': 'Whole clinic'},
];

/// The clinic's working day on Firebase, for the staff website: appointments, the queue,
/// holds, the waitlist, staff, the message outbox and the audit log, kept live by listeners.
/// What each role can read and change is enforced by firestore.rules; this class only asks
/// for what the signed-in role is allowed.
class ClinicDesk extends ChangeNotifier {
  ClinicDesk(this._db, this.clinicId, this.me, {ClinicClock? clock}) : clock = clock ?? ClinicClock.real() {
    final c = _clinic;
    _watchDays();
    _subs
      ..add(c.collection('blocks').snapshots().listen((q) {
        blocks = [
          for (final d in q.docs)
            DeskBlock(
              id: d.id,
              clinicianId: d.data()['clinicianId'] ?? '',
              type: d.data()['type'] ?? 'Unavailable',
              minutes: d.data()['minutes'] == null ? null : Set<int>.from(d.data()['minutes']),
              date: d.data()['date'],
            ),
        ];
        _changed();
      }, onError: _failed))
      ..add(c.collection('staff').snapshots().listen((q) {
        staff = [for (final d in q.docs) StaffMember.fromDoc(d.id, d.data())]..sort((a, b) => a.name.compareTo(b.name));
        _changed();
      }, onError: _failed))
      ..add(c.collection('templates').snapshots().listen((q) {
        templates = {for (final d in q.docs) d.id: Map<String, String>.from(d.data().map((k, v) => MapEntry(k, '$v')))};
        _changed();
      }, onError: _failed));
    if (me.runsDay) {
      _subs
        ..add(c.collection('waitlist').snapshots().listen((q) {
          waitlist = [
            for (final d in q.docs)
              WaitlistEntry(
                uid: d.id,
                name: '${d.data()['name'] ?? 'Patient'}',
                appointmentId: '${d.data()['appointmentId'] ?? ''}',
                serviceId: '${d.data()['serviceId'] ?? ''}',
                // a malformed entry shouldn't take the page down: no visit means "any earlier time"
                date: d.data()['date'] is String ? d.data()['date'] : '9999-12-31',
                minute: d.data()['minute'] is int ? d.data()['minute'] : 24 * 60,
                clinicianId: d.data()['clinicianId'],
                days: Set<String>.from(d.data()['days'] ?? const []),
                parts: {for (final p in d.data()['parts'] ?? const []) ?DayPart.values.asNameMap()[p]},
                joinedAt: DateTime.fromMillisecondsSinceEpoch(d.data()['joinedAt'] ?? 0),
                priority: d.data()['priority'] ?? false,
                passed: d.data()['passed'] ?? 0,
                offer: d.data()['offer'] as Map<String, dynamic>?,
              ),
          ]..sort((a, b) => a.priority == b.priority ? a.joinedAt.compareTo(b.joinedAt) : (a.priority ? -1 : 1));
          _changed();
        }, onError: _failed))
        ..add(c.collection('outbox').orderBy('at', descending: true).limit(100).snapshots().listen((q) {
          outbox = [
            for (final d in q.docs)
              OutboxMessage(
                id: d.id,
                to: d.data()['to'] ?? '',
                message: d.data()['message'] ?? '',
                channel: d.data()['channel'] ?? '',
                status: d.data()['status'] ?? 'queued',
                at: (d.data()['at'] as Timestamp?)?.toDate(),
              ),
          ];
          _changed();
        }, onError: _failed));
    }
    if (me.isAdmin) {
      _subs.add(c.collection('audit').orderBy('at', descending: true).limit(500).snapshots().listen((q) {
        audit = [
          for (final d in q.docs)
            AuditEntry(
              at: (d.data()['at'] as Timestamp?)?.toDate(),
              actor: d.data()['actor'] ?? '',
              action: d.data()['action'] ?? '',
              record: d.data()['record'] ?? '',
              detail: d.data()['detail'] ?? '',
            ),
        ];
        _changed();
      }, onError: _failed));
    }
    // waits, lateness and holds move with the clock, not only with the database
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (today != _watchedDay) _watchDays();
      notifyListeners();
    });
  }

  /// Listens to what depends on the date: appointments from 5 weeks back (for missed visits
  /// and reports) onward, slots and holds from today, and today's queue. Called again at midnight.
  void _watchDays() {
    for (final s in _daySubs) {
      s.cancel();
    }
    _daySubs.clear();
    final c = _clinic;
    _watchedDay = today;
    final from = addDays(today, -35);
    final appts = me.role == 'clinician'
        ? c.collection('appointments').where('clinicianId', isEqualTo: me.clinicianId ?? '-').where('date', isGreaterThanOrEqualTo: from)
        : c.collection('appointments').where('date', isGreaterThanOrEqualTo: from);
    if (!me.readOnly) {
      _daySubs.add(appts.snapshots().listen((q) {
        appointments = [for (final d in q.docs) DeskAppt.fromDoc(d.id, d.data())]..sort((a, b) => a.date == b.date ? a.minute - b.minute : a.date.compareTo(b.date));
        _changed();
      }, onError: _failed));
    }
    _daySubs
      ..add(c.collection('slots').where('date', isGreaterThanOrEqualTo: today).snapshots().listen((q) {
        _slots = {for (final d in q.docs) d.id: d.data()['appointmentId'] as String?};
        _changed();
      }, onError: _failed))
      ..add(c.collection('holds').where('date', isGreaterThanOrEqualTo: today).snapshots().listen((q) {
        _holds = {for (final d in q.docs) d.id: d.data()};
        _changed();
      }, onError: _failed))
      ..add(c.collection('queue').where('date', isEqualTo: today).snapshots().listen((q) {
        queue = [for (final d in q.docs) d.data()];
        _changed();
      }, onError: _failed));
  }

  final FirebaseFirestore _db;
  final String clinicId;
  final StaffMember me;

  /// Real time, or the sample morning when testing against the seeded emulators.
  final ClinicClock clock;
  final _subs = <StreamSubscription<dynamic>>[];
  final _daySubs = <StreamSubscription<dynamic>>[];
  String _watchedDay = '';
  Timer? _ticker;

  List<DeskAppt> appointments = const [];
  List<DeskBlock> blocks = const [];
  List<Map<String, dynamic>> queue = const [];
  List<StaffMember> staff = const [];
  List<WaitlistEntry> waitlist = const [];
  List<OutboxMessage> outbox = const [];
  List<AuditEntry> audit = const [];
  Map<String, Map<String, String>> templates = const {};
  var _slots = <String, String?>{}; // clinician_date_minute -> appointment id
  var _holds = <String, Map<String, dynamic>>{};

  /// The last listener error, if a read was refused (usually: the rules weren't deployed yet).
  String? error;

  DocumentReference<Map<String, dynamic>> get _clinic => _db.collection('clinics').doc(clinicId);

  void _changed() {
    error = null;
    notifyListeners();
  }

  void _failed(Object e) {
    error = '$e';
    debugPrint('ClinicDesk: $e');
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in [..._subs, ..._daySubs]) {
      s.cancel();
    }
    _ticker?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- the clock
  String get today => clock.today;
  int get nowMinute => clock.minute;
  static String key(String clinicianId, String date, int minute) => '${clinicianId}_${date}_$minute';

  // ---------------------------------------------------------------- reading the days
  List<DeskAppt> on(String date) => appointments.where((a) => a.date == date).toList();
  List<DeskAppt> get todayVisits => on(today);

  /// The live (not cancelled, not missed) appointment at this time.
  DeskAppt? apptAt(String clinicianId, String date, int minute) =>
      appointments.where((a) => a.clinicianId == clinicianId && a.date == date && a.minute == minute && a.active).firstOrNull;

  bool isLate(DeskAppt a) => a.status == ApptStatus.late || (a.status.upcoming && a.date == today && nowMinute > a.minute + 5);
  int lateBy(DeskAppt a) => (nowMinute - a.minute).clamp(0, 600);
  int waited(DeskAppt a) => (nowMinute - (a.waitingSince ?? a.checkedInAt ?? nowMinute)).clamp(0, 600);

  /// What makes a time unbookable for this clinician: a break, time off, or outside their
  /// days and hours (from setup). Null if they're in and free to be booked.
  String? unavailable(SetupClinician c, int minute, String date) {
    final b = blocks.where((b) => b.clinicianId == c.id && b.covers(minute, date)).firstOrNull;
    if (b != null) return b.type;
    if (!c.days.contains(weekdayOf(date)) || minute < c.start || minute >= c.end) return 'Not in';
    return null;
  }

  /// Bookable times for this clinician on [date], and how many of them are booked.
  int capacity(SetupClinician c, String date) => slotMinutes.where((m) => unavailable(c, m, date) == null || on(date).any((a) => a.clinicianId == c.id && a.minute == m && a.active)).length;
  int booked(SetupClinician c, String date) => on(date).where((a) => a.clinicianId == c.id && a.active).length;

  /// A live hold on this time: "patient" (someone booking online) or "desk".
  String? heldBy(String clinicianId, String date, int minute) {
    final h = _holds[key(clinicianId, date, minute)];
    if (h == null || (h['expiresAt'] as int) <= DateTime.now().millisecondsSinceEpoch) return null;
    return '${h['owner']}'.startsWith('desk') ? 'desk' : 'patient';
  }

  bool heldByMe(String clinicianId, String date, int minute) {
    final h = _holds[key(clinicianId, date, minute)];
    return h != null && h['holderUid'] == me.uid && (h['expiresAt'] as int) > DateTime.now().millisecondsSinceEpoch;
  }

  bool taken(String clinicianId, String date, int minute) => _slots.containsKey(key(clinicianId, date, minute));

  /// Times freed by cancellations that are still ahead, soonest first.
  List<FreedSlot> get freed {
    final out = <FreedSlot>[];
    for (final a in appointments.where((a) => a.status == ApptStatus.cancelled && a.date.compareTo(today) >= 0)) {
      if (out.any((f) => f.clinicianId == a.clinicianId && f.date == a.date && f.minute == a.minute)) continue;
      final now = apptAt(a.clinicianId, a.date, a.minute);
      final offered = waitlist
          .where((w) => w.offerLive && w.offer!['clinicianId'] == a.clinicianId && (w.offer!['date'] ?? today) == a.date && w.offer!['minute'] == a.minute)
          .firstOrNull;
      if (now == null && clock.passed(a.date, a.minute)) continue; // passed without being refilled
      out.add(FreedSlot(clinicianId: a.clinicianId, date: a.date, minute: a.minute, cancelled: a, refilledBy: now?.patientName, offeredTo: offered));
    }
    return out..sort((a, b) => a.date == b.date ? a.minute - b.minute : a.date.compareTo(b.date));
  }

  /// The visits that didn't happen, newest first.
  List<DeskAppt> get missed => appointments.where((a) => a.status == ApptStatus.noShow).toList()..sort((a, b) => b.date.compareTo(a.date) == 0 ? b.minute - a.minute : b.date.compareTo(a.date));

  String template(String k, String lang) => templates[k]?[lang] ?? (lang == 'en' ? messageTemplates[k]!.$2 : '');

  // ---------------------------------------------------------------- writing, with an audit trail
  Future<void> _audit(String action, String record, String detail) => _clinic.collection('audit').add({
        'at': FieldValue.serverTimestamp(),
        'actorUid': me.uid,
        'actor': '${me.name.isEmpty ? me.email : me.name} (${me.role})',
        'action': action,
        'record': record,
        'detail': detail,
      }).then((_) {}, onError: (Object e) => debugPrint('audit not written: $e'));

  /// Queues a message. Cloud Functions will send it by push, text or email and record how it went.
  Future<void> _send(String to, String message, String channel, [String? appointmentId]) => _clinic.collection('outbox').add({
        'at': FieldValue.serverTimestamp(),
        'by': me.uid,
        'to': to,
        'message': message,
        'channel': channel,
        'appointmentId': appointmentId,
        'status': 'queued',
      });

  /// Moves a visit along: Checked in, Waiting, In visit, Complete, or No-show.
  /// Checking in hands out the next ticket number, which is returned.
  Future<String?> setStatus(DeskAppt a, ApptStatus to) async {
    final ref = _clinic.collection('appointments').doc(a.id);
    if (to == ApptStatus.checkedIn) {
      // ticket numbers start over each day, like the patient app's check-in
      final counterRef = _clinic.collection('counters').doc('tickets-${a.date}');
      final ticket = await _db.runTransaction<String>((tx) async {
        final counter = await tx.get(counterRef);
        final n = (counter.data()?['next'] as int?) ?? 1;
        final t = 'A-$n';
        tx.set(counterRef, {'next': n + 1});
        tx.update(ref, {'status': to.name, 'ticket': t, 'checkedInAt': nowMinute});
        tx.set(_queueDoc(a.date, t), {'ticket': t, 'n': n, 'date': a.date, 'clinicianId': a.clinicianId, 'status': to.name});
        return t;
      });
      await _audit('appointment.checkin', a.id, '${a.patientName} · ticket $ticket');
      return ticket;
    }
    final batch = _db.batch()
      ..update(ref, {
        'status': to.name,
        if (to == ApptStatus.waiting) 'waitingSince': nowMinute,
        if (to == ApptStatus.inVisit) 'calledAt': nowMinute,
        if (to == ApptStatus.noShow) 'followUp': 'open',
      });
    if (a.ticket != null) batch.set(_queueDoc(a.date, a.ticket!), {'status': to.name}, SetOptions(merge: true));
    await batch.commit();
    await _audit('appointment.status', a.id, '${a.patientName}: ${a.status.label} → ${to.label}');
    return null;
  }

  DocumentReference<Map<String, dynamic>> _queueDoc(String date, String ticket) => _clinic.collection('queue').doc('${date}_$ticket');

  /// Undo: puts a visit back to [to] (its status before [from]) without handing out a new ticket.
  Future<void> revert(DeskAppt a, ApptStatus from, ApptStatus to) async {
    final batch = _db.batch()
      ..update(_clinic.collection('appointments').doc(a.id), {
        'status': to.name,
        if (from == ApptStatus.noShow) 'followUp': FieldValue.delete(),
      });
    if (a.ticket != null) batch.set(_queueDoc(a.date, a.ticket!), {'status': to.name}, SetOptions(merge: true));
    await batch.commit();
    await _audit('appointment.undo', a.id, '${a.patientName}: ${from.label} → ${to.label}');
  }

  /// "Thu Oct 29, 9:00 am".
  static String _when(String date, int minute) => '${shortDate(date)}, ${formatTime(minute)}';

  /// The clinic cancels a visit; the time is freed for the waitlist and the patient is told.
  Future<void> cancel(DeskAppt a, String reason) async {
    final batch = _db.batch()
      ..update(_clinic.collection('appointments').doc(a.id), {'status': ApptStatus.cancelled.name, 'cancelledBy': 'clinic'})
      ..delete(_clinic.collection('slots').doc(key(a.clinicianId, a.date, a.minute)));
    await batch.commit();
    await _send(a.patientName, 'Cancellation, clinic cancelled ($reason)', 'Text and email', a.id);
    await _audit('appointment.cancel', a.id, '${a.patientName} · ${_when(a.date, a.minute)} · $reason');
  }

  Future<void> remind(DeskAppt a) async {
    await _send(a.patientName, 'Reminder, one-tap confirm', 'Push, then text', a.id);
    await _audit('notification.queued', a.id, 'Reminder to ${a.patientName}');
  }

  Future<void> sendForm(DeskAppt a) async {
    await _send(a.patientName, 'Reason-for-visit form link', 'Push, then text', a.id);
    await _audit('notification.queued', a.id, 'Form link to ${a.patientName}');
  }

  Future<void> text(DeskAppt a, String message) async {
    await _send(a.patientName, message, 'Text', a.id);
    await _audit('notification.queued', a.id, 'Text to ${a.patientName}');
  }

  // ---------------------------------------------------------------- booking at the front desk
  /// Holds a time for 2 minutes while the front desk books it, like a patient's 5-minute hold.
  /// False if someone else is holding or has taken it.
  Future<bool> hold(String clinicianId, String date, int minute) async {
    if (taken(clinicianId, date, minute)) return false;
    try {
      await _clinic.collection('holds').doc(key(clinicianId, date, minute)).set({
        'owner': 'desk#${me.uid}',
        'holderUid': me.uid,
        'clinicianId': clinicianId,
        'date': date,
        'minute': minute,
        'expiresAt': DateTime.now().add(const Duration(minutes: 2)).millisecondsSinceEpoch,
      });
      return true;
    } on FirebaseException {
      return false; // the rules refuse: a patient's hold is still live
    }
  }

  Future<void> release(String clinicianId, String date, int minute) async {
    if (heldByMe(clinicianId, date, minute)) await _clinic.collection('holds').doc(key(clinicianId, date, minute)).delete();
  }

  /// Books a held time for a patient on the phone or at the desk. The slot document is the
  /// same double-booking guard the patient app uses, so two bookings can never share a time.
  Future<BookingOutcome> book({
    required String name,
    required String phone,
    required String serviceId,
    required String clinicianId,
    required String date,
    required int minute,
  }) async {
    final k = key(clinicianId, date, minute), slotRef = _clinic.collection('slots').doc(k), holdRef = _clinic.collection('holds').doc(k);
    final apptRef = _clinic.collection('appointments').doc(), digits = phone.replaceAll(RegExp(r'\D'), '');
    final outcome = await _db.runTransaction<BookingOutcome>((tx) async {
      final slot = await tx.get(slotRef), held = await tx.get(holdRef);
      if (slot.exists) return BookingOutcome.slotTaken;
      if (!held.exists || held['holderUid'] != me.uid || (held['expiresAt'] as int) <= DateTime.now().millisecondsSinceEpoch) return BookingOutcome.holdExpired;
      tx.set(slotRef, {'appointmentId': apptRef.id, 'clinicianId': clinicianId, 'date': date, 'minute': minute});
      tx.set(apptRef, {
        'clinicianId': clinicianId,
        'serviceId': serviceId,
        'patientName': name.trim(),
        'patientUid': null,
        'phone': digits,
        'phoneLast4': digits.length >= 4 ? digits.substring(digits.length - 4) : null,
        'minute': minute,
        'date': date,
        'status': ApptStatus.booked.name, // confirmed when the patient taps the reminder
        'formsDone': false,
        'bookedBy': me.uid,
      });
      tx.delete(holdRef);
      return BookingOutcome.booked;
    });
    if (outcome == BookingOutcome.booked) {
      await _send(name.trim(), 'Booking confirmation', 'Text, then email', apptRef.id);
      await _audit('appointment.create', apptRef.id, 'Front desk booking · ${name.trim()} · ${_when(date, minute)}');
    }
    return outcome;
  }

  // ---------------------------------------------------------------- check-in tablet
  /// Today's visits not yet checked in whose phone number ends in [last4].
  List<DeskAppt> findForCheckIn(String last4) => todayVisits.where((a) => a.phoneLast4 == last4 && a.status.upcoming).toList();

  // ---------------------------------------------------------------- waitlist
  /// Offers a freed time to someone on the waitlist. It's held for them for the clinic's
  /// offer time; they accept or decline in the patient app.
  Future<void> offer(FreedSlot f, WaitlistEntry w, int holdMinutes) async {
    final expires = DateTime.now().add(Duration(minutes: holdMinutes)).millisecondsSinceEpoch;
    final batch = _db.batch()
      ..set(_db.collection('patients').doc(w.uid).collection('offers').doc(), {
        'clinicId': clinicId,
        'clinicianId': f.clinicianId,
        'date': f.date,
        'minute': f.minute,
        'appointmentId': w.appointmentId,
        'expiresAt': expires,
        'by': me.uid,
      })
      ..update(_clinic.collection('waitlist').doc(w.uid), {'offer': {'clinicianId': f.clinicianId, 'date': f.date, 'minute': f.minute, 'expiresAt': expires}});
    await batch.commit();
    await _send(w.name, 'Waitlist offer: ${_when(f.date, f.minute)}', 'Push and text');
    await _audit('waitlist.offer', w.uid, '${w.name} · ${_when(f.date, f.minute)} · held $holdMinutes min');
  }

  Future<void> setPriority(WaitlistEntry w, bool on) async {
    await _clinic.collection('waitlist').doc(w.uid).update({'priority': on});
    await _audit('waitlist.priority', w.uid, '${w.name}: ${on ? 'priority' : 'normal order'}');
  }

  // ---------------------------------------------------------------- missed visits
  /// 'contacted' (sends a rebooking link), 'rebooked', 'excused' (kept out of the no-show rate) or 'open'.
  Future<void> followUp(DeskAppt a, String state) async {
    await _clinic.collection('appointments').doc(a.id).update({'followUp': state});
    if (state == 'contacted') await _send(a.patientName, 'Missed visit follow-up with rebooking link', 'Text, then email', a.id);
    await _audit('missed.$state', a.id, '${a.patientName} · ${a.date} ${formatTime(a.minute)}');
  }

  // ---------------------------------------------------------------- clinic settings (admins)
  Future<void> addBlock({required String clinicianId, required String type, required String date, Set<int>? minutes}) async {
    await _clinic.collection('blocks').add({'clinicianId': clinicianId, 'type': type, 'date': date, 'minutes': minutes?.toList()});
    await _audit('schedule.timeoff', clinicianId, '$type · $date${minutes == null ? ' · all day' : ' · ${minutes.map(formatTime).join(', ')}'}');
  }

  Future<void> removeBlock(DeskBlock b) async {
    await _clinic.collection('blocks').doc(b.id).delete();
    await _audit('schedule.timeoff.removed', b.clinicianId, '${b.type} · ${b.date ?? 'every day'}');
  }

  Future<void> setBlockTypes(List<Map<String, String>> types, String change) async {
    await _clinic.update({'blockTypes': types});
    await _audit('settings.update', 'CLINIC', change);
  }

  Future<void> saveTemplate(String k, {required String en, required String fr}) async {
    await _clinic.collection('templates').doc(k).set({'en': en, 'fr': fr});
    await _audit('settings.template', k, messageTemplates[k]!.$1);
  }

  /// Shows on every patient's home screen for this clinic until cleared.
  Future<void> announce(String text) async {
    await _clinic.update({'notice': text.trim()});
    await _send('Patients with visits this week', 'Clinic announcement: ${text.trim()}', 'Push, then email');
    await _audit('notification.announcement', 'CLINIC', text.trim());
  }

  Future<void> clearAnnouncement() async {
    await _clinic.update({'notice': FieldValue.delete()});
    await _audit('notification.announcement.cleared', 'CLINIC', '');
  }

  Future<void> setRole(StaffMember s, String role) async {
    await _clinic.collection('staff').doc(s.uid).update({'role': role});
    await _audit('role.update', s.uid, '${s.name}: ${s.role} → $role');
  }

  Future<void> linkClinician(StaffMember s, String? clinicianId) async {
    await _clinic.collection('staff').doc(s.uid).update({'clinicianId': clinicianId});
    await _audit('role.update', s.uid, '${s.name} is clinician ${clinicianId ?? 'none'}');
  }

  Future<void> removeStaff(StaffMember s) async {
    await _clinic.collection('staff').doc(s.uid).delete();
    await _audit('user.removed', s.uid, s.name);
  }

  Future<void> record(String action, String record, String detail) => _audit(action, record, detail);
}
