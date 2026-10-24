// Data models shared by the patient app, the staff app and the admin website.
// They mirror the records described for Firestore: clinics, clinicians, services,
// unavailable time, appointments and temporary slot holds.

/// Bookable start times for the day, in minutes after midnight:
/// 9:00 to 11:30 and 1:00 to 4:30, every 30 minutes (the prototype's day).
const List<int> slotMinutes = [540, 570, 600, 630, 660, 690, 780, 810, 840, 870, 900, 930, 960, 990];

/// How far ahead patients can book online.
const bookingDays = 14;

/// 9:30 am in English, 9 h 30 in French.
String formatTime(int minute, {String lang = 'en'}) {
  final h = minute ~/ 60, m = (minute % 60).toString().padLeft(2, '0');
  if (lang == 'fr') return '$h h $m';
  return '${h > 12 ? h - 12 : h}:$m ${h >= 12 ? 'pm' : 'am'}';
}

// ---------------------------------------------------------------- dates
// Days travel as 'YYYY-MM-DD' strings: they sort, compare and key documents the same everywhere.

String isoDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [date] plus [days], as a date string.
String addDays(String date, int days) {
  final d = DateTime.parse(date);
  return isoDate(DateTime(d.year, d.month, d.day + days));
}

/// The next [count] days from [from], [from] first.
List<String> daysFrom(String from, int count) => [for (var i = 0; i < count; i++) addDays(from, i)];

const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Thu" for a Thursday.
String weekdayOf(String date) => weekdayNames[DateTime.parse(date).weekday - 1];

const _monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsFr = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const _daysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _daysFr = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

/// "Thu Oct 29" / "jeu. 29 oct.".
String shortDate(String date, {String lang = 'en'}) {
  final d = DateTime.parse(date);
  return lang == 'fr' ? '${_daysFr[d.weekday - 1].substring(0, 3)}. ${d.day} ${_monthsFr[d.month - 1]}' : '${weekdayNames[d.weekday - 1]} ${_monthsEn[d.month - 1]} ${d.day}';
}

/// "Today", "Tomorrow", or "Thu Oct 29", relative to [today]. [midSentence] gives
/// "today" and "tomorrow" in lower case; dates keep their capitals.
String dayLabel(String date, String today, {String lang = 'en', bool midSentence = false}) {
  String word(String w) => midSentence ? w.toLowerCase() : w;
  if (date == today) return word(lang == 'fr' ? 'Aujourd’hui' : 'Today');
  if (date == addDays(today, 1)) return word(lang == 'fr' ? 'Demain' : 'Tomorrow');
  return shortDate(date, lang: lang);
}

/// "Today, Thursday Oct 23" / "Aujourd’hui, jeudi 23 oct.": for headings.
String longDay(String date, String today, {String lang = 'en'}) {
  final d = DateTime.parse(date);
  final full = lang == 'fr' ? '${_daysFr[d.weekday - 1]} ${d.day} ${_monthsFr[d.month - 1]}' : '${_daysEn[d.weekday - 1]} ${_monthsEn[d.month - 1]} ${d.day}';
  if (date == today) return '${lang == 'fr' ? 'Aujourd’hui' : 'Today'}, $full';
  if (date == addDays(today, 1)) return '${lang == 'fr' ? 'Demain' : 'Tomorrow'}, $full';
  return full[0].toUpperCase() + full.substring(1);
}

/// "Oct 23, 2026": for records like visit history.
String recordDate(String date) {
  final d = DateTime.parse(date);
  return '${_monthsEn[d.month - 1]} ${d.day}, ${d.year}';
}

/// The clinic's clock. Real time in the apps; sample data and tests can start it at a
/// chosen moment (9:41 this morning), after which it runs at normal speed.
class ClinicClock {
  ClinicClock.real() : _offset = Duration.zero;
  ClinicClock.startingAt(DateTime start) : _offset = start.difference(DateTime.now());

  /// Today at [minute] (9:41 am by default): the sample day, on today's real date.
  factory ClinicClock.sampleMorning({int minute = 9 * 60 + 41}) {
    final n = DateTime.now();
    return ClinicClock.startingAt(DateTime(n.year, n.month, n.day, minute ~/ 60, minute % 60));
  }

  final Duration _offset;
  DateTime now() => DateTime.now().add(_offset);
  String get today => isoDate(now());

  /// Minutes after midnight, now.
  int get minute {
    final n = now();
    return n.hour * 60 + n.minute;
  }

  /// Has [date] at [minute] already started?
  bool passed(String date, int minute) => date.compareTo(today) < 0 || (date == today && minute <= this.minute);

  /// Hours from now until [date] at [minute] (negative if past).
  double hoursUntil(String date, int minute) {
    final d = DateTime.parse(date);
    return DateTime(d.year, d.month, d.day, minute ~/ 60, minute % 60).difference(now()).inMinutes / 60;
  }
}

/// A visit moves Booked → Confirmed → Checked in → Waiting → In visit → Complete.
/// [arrived] separates "not here yet" (outlined dot) from "here" (filled dot).
enum ApptStatus {
  booked('Booked', arrived: false),
  confirmed('Confirmed', arrived: false),
  late('Late', arrived: false),
  checkedIn('Checked in', arrived: true),
  waiting('Waiting', arrived: true),
  inVisit('In visit', arrived: true),
  complete('Complete', arrived: true),
  noShow('No-show', arrived: false),
  cancelled('Cancelled', arrived: false);

  const ApptStatus(this.label, {required this.arrived});
  final String label;
  final bool arrived;

  bool get active => this != noShow && this != cancelled;
  bool get upcoming => this == booked || this == confirmed || this == late;
}

class Clinic {
  const Clinic({
    required this.id,
    required this.initials,
    required this.name,
    required this.address,
    required this.kind,
    required this.lat,
    required this.lng,
    this.accepting = true,
    this.isHome = false,
    this.notice,
    this.listed = true,
  });
  final String id, initials, name, address;

  /// In the directory: set up, approved by ClinicFlow and opted in. A visit at a clinic
  /// that isn't (any more) still shows the clinic's details to the patient who booked it.
  final bool listed;

  /// The clinic's current announcement to patients, if any ("Parking lot B is closed...").
  final String? notice;

  /// What the clinic offers, as shown in the directory: "Physiotherapy, chiropractic".
  final String kind;
  final double lat, lng;

  /// False means waitlist only: no online booking.
  final bool accepting;

  /// The patient's own clinic (Maple Grove in the sample data).
  final bool isHome;
}

class Clinician {
  const Clinician({
    required this.id,
    required this.clinicId,
    required this.name,
    required this.short,
    required this.role,
    this.roleFr = '',
  });
  final String id, clinicId, name, short, role, roleFr;
  String roleIn(String lang) => lang == 'fr' && roleFr.isNotEmpty ? roleFr : role;
}

class Service {
  const Service({
    required this.id,
    required this.clinicId,
    required this.name,
    required this.short,
    required this.minutes,
    required this.clinicianIds,
    this.nameFr = '',
    this.who = '',
    this.whoFr = '',
    this.online = true,
  });
  final String id, clinicId, name, nameFr, short, who, whoFr;
  final int minutes;
  final bool online;
  final List<String> clinicianIds;
  String nameIn(String lang) => lang == 'fr' && nameFr.isNotEmpty ? nameFr : name;
  String whoIn(String lang) => lang == 'fr' && whoFr.isNotEmpty ? whoFr : who;
}

/// Unavailable time: a break, "Not in", vacation. [minutes] null means the whole day;
/// [date] null means every day.
class Block {
  const Block({required this.clinicianId, required this.type, this.minutes, this.date});
  final String clinicianId, type;
  final Set<int>? minutes;
  final String? date;
  bool covers(String day, int minute) => (date == null || date == day) && (minutes == null || minutes!.contains(minute));
}

/// When a clinician works: weekdays ('Mon'...) and hours, in minutes after midnight.
class WorkHours {
  const WorkHours({required this.days, required this.start, required this.end});
  final Set<String> days;
  final int start, end;
  static const weekdays9to5 = WorkHours(days: {'Mon', 'Tue', 'Wed', 'Thu', 'Fri'}, start: 540, end: 1020);
  bool covers(String date, int minute) => days.contains(weekdayOf(date)) && minute >= start && minute < end;
}

class Appointment {
  Appointment({
    required this.id,
    required this.clinicId,
    required this.clinicianId,
    required this.serviceId,
    required this.patientName,
    required this.date,
    required this.minute,
    this.status = ApptStatus.booked,
    this.ticket,
    this.formsDone = false,
    this.phoneLast4,
    this.mine = false,
    this.bookedByGuardian = false,
  });
  final String id, clinicId, serviceId, patientName;

  /// Change only through a reschedule or an accepted waitlist offer.
  String clinicianId;

  /// The day ('2026-10-23') and start time (minutes after midnight).
  String date;
  int minute;

  /// Earliest first: by day, then time.
  static int byTime(Appointment a, Appointment b) => a.date == b.date ? a.minute - b.minute : a.date.compareTo(b.date);
  ApptStatus status;
  String? ticket;
  bool formsDone;
  final String? phoneLast4;

  /// Booked by the signed-in patient (for themselves or someone they care for).
  final bool mine;
  final bool bookedByGuardian;
  int? checkedInAt;
}

/// A slot held while someone finishes booking it (5 minutes online, 2 at the front desk).
class Hold {
  const Hold({required this.clinicianId, required this.date, required this.minute, required this.owner, required this.expiresAt});
  final String clinicianId, date, owner;
  final int minute;
  final DateTime expiresAt;
  Duration get left {
    final d = expiresAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  bool get live => left > Duration.zero;
}

enum SlotState { free, taken, blocked, held, past }

class BookingRequest {
  const BookingRequest({
    required this.clinicId,
    required this.serviceId,
    required this.clinicianId,
    required this.date,
    required this.minute,
    required this.patientName,
    required this.phone,
    required this.owner,
    this.email = '',
    this.bookedByGuardian = false,
  });
  final String clinicId, serviceId, clinicianId, date, patientName, phone, email, owner;
  final int minute;
  final bool bookedByGuardian;
}

enum BookingOutcome { booked, slotTaken, holdExpired }

class BookingResult {
  const BookingResult(this.outcome, [this.appointment]);
  final BookingOutcome outcome;
  final Appointment? appointment;
}

/// Thrown when a phone number already has two unconfirmed bookings today.
class RateLimitException implements Exception {
  const RateLimitException();
}

// ---------------------------------------------------------------- the patient's own records

/// What a notification is about, written out so it never relies on colour alone.
enum NoticeKind {
  reminder('Reminder'),
  todo('To do'),
  update('Update'),
  offer('Offer'),
  notice('Notice');

  const NoticeKind(this.label);
  final String label;
}

/// The one-tap action a notification offers, if any.
enum NoticeAction { confirm, intake, offer }

class PatientNotice {
  const PatientNotice({required this.text, required this.when, required this.kind, this.action});
  final String text, when;
  final NoticeKind kind;
  final NoticeAction? action;
}

/// Someone the patient books for: a child, a parent, a partner.
class FamilyMember {
  const FamilyMember({required this.id, required this.name, required this.relationship, this.born});
  final String id, name, relationship;
  final DateTime? born;
}

/// The reason-for-visit form. Operational only: nothing clinical is collected.
class IntakeAnswers {
  const IntakeAnswers({required this.visitType, this.note = '', this.contactByText = false});
  final String visitType, note;
  final bool contactByText;
  static const visitTypes = ['Follow-up visit', 'First visit at this clinic', 'Routine check'];
}

enum DayPart {
  morning('Morning'),
  afternoon('Afternoon'),
  after4('After 4 pm');

  const DayPart(this.label);
  final String label;

  static DayPart of(int minute) => minute < 720 ? morning : minute < 960 ? afternoon : after4;
}

/// When the patient could come instead, if a time opens up. [clinicianId] null means anyone.
class WaitlistRequest {
  const WaitlistRequest({required this.days, required this.parts, this.clinicianId});
  final Set<String> days;
  final Set<DayPart> parts;
  final String? clinicianId;
  static const weekdays = weekdayNames;
}

/// A freed slot held for this patient for a short time (15 minutes by default).
class WaitlistOffer {
  const WaitlistOffer({required this.clinicianId, required this.date, required this.minute, required this.expiresAt, required this.appointmentId});
  final String clinicianId, date, appointmentId;
  final int minute;
  final DateTime expiresAt;
  bool get live => expiresAt.isAfter(DateTime.now());
}

class PastVisit {
  PastVisit({required this.date, required this.service, required this.clinician, required this.clinic, required this.fee, required this.owing, required this.who});
  final String date, service, clinician, clinic, who;
  final double fee;
  double owing;
}
