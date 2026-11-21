// The pure parts of ClinicFlow's messages: clinic-time arithmetic, message wording and the
// waitlist match. No Firebase here, so it's tested on its own (node test.js).

const TIME_ZONE = 'America/Toronto';
const PATIENT_APP = 'https://clinicflow-9e598.web.app';
const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// ---------------------------------------------------------------- clinic time
// Visits are stored as a local date ("2026-11-12") and minutes after midnight (600 = 10:00 am),
// in the clinic's time zone. Every ClinicFlow clinic is in Ontario for now.

const parts = new Intl.DateTimeFormat('en-CA', {
  timeZone: TIME_ZONE, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit',
});

/** How far the clinic's clock is ahead of UTC at [ms], in ms (negative in Canada). */
function zoneOffset(ms) {
  const p = Object.fromEntries(parts.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second) - Math.floor(ms / 1000) * 1000;
}

/** The moment a visit starts. */
function visitTime(date, minute) {
  const [y, m, d] = date.split('-').map(Number);
  const asUtc = Date.UTC(y, m - 1, d, 0, minute);
  const first = asUtc - zoneOffset(asUtc);
  return asUtc - zoneOffset(first); // a second pass settles the days the clocks change
}

/** Today's date at the clinic, "2026-11-09". */
function clinicDate(ms = Date.now(), plusDays = 0) {
  const p = Object.fromEntries(parts.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  const d = new Date(Date.UTC(+p.year, +p.month - 1, +p.day + plusDays));
  return d.toISOString().slice(0, 10);
}

/** "Mon", "Tue"... for a date, as the waitlist stores the days a patient can come. */
function weekday(date) {
  const [y, m, d] = date.split('-').map(Number);
  return WEEKDAYS[(new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7];
}

/** Morning, afternoon or after 4 pm, as in the patient app (DayPart.of). */
function dayPart(minute) {
  return minute < 720 ? 'morning' : minute < 960 ? 'afternoon' : 'after4';
}

/** "Thu Nov 12" */
function shortDate(date) {
  const [y, m, d] = date.split('-').map(Number);
  return `${weekday(date)} ${MONTHS[m - 1]} ${d}`;
}

/** "10:00 am" */
function formatTime(minute) {
  const h = Math.floor(minute / 60), m = minute % 60;
  return `${((h + 11) % 12) + 1}:${String(m).padStart(2, '0')} ${h < 12 ? 'am' : 'pm'}`;
}

// ---------------------------------------------------------------- wording
// The clinic can change any of these in the staff website (clinics/{id}/templates/{key}).
const DEFAULT_TEMPLATES = {
  confirm: "Hi {first_name}, you're booked: {service} with {clinician} on {date} at {time}, {clinic}. See or change it: {link}",
  reminder48: 'Hi {first_name}, reminder: {service} with {clinician} on {date} at {time}, {clinic}. Tap to confirm: {link}. Need to change it? Same link. Reply STOP to opt out.',
  reminder24: 'Hi {first_name}, reminder: {service} with {clinician} tomorrow at {time}, {clinic}. Tap to confirm: {link}. Need to change it? Same link. Reply STOP to opt out.',
  cancelClinic: "Hi {first_name}, we're sorry: we had to cancel your {service} with {clinician} on {date} at {time} ({reason}). You're first in line for a new time: {link}",
  offer: 'Hi {first_name}, an earlier time opened at {clinic}: {date} at {time} with {clinician}. It is held for you for {hold} minutes. Accept or pass in the app: {link}',
};

/** What the staff website's delivery log calls each message. */
const LABELS = {
  confirm: 'Booking confirmation',
  reminder48: 'Reminder, 48 h before',
  reminder24: 'Reminder, 24 h before',
  cancelClinic: 'Cancellation, clinic cancelled',
  offer: 'Waitlist offer',
};

/** Which message a staff-website outbox entry asks for, from its label. */
function kindOf(entry) {
  if (entry.kind) return entry.kind;
  const m = entry.message || '';
  if (m.startsWith('Booking confirmation')) return 'confirm';
  if (m.startsWith('Cancellation, clinic cancelled')) return 'cancelClinic';
  if (m.startsWith('Reminder')) return 'reminder48'; // a reminder sent by hand: the wording without "tomorrow"
  if (m.startsWith('Waitlist offer')) return 'offer';
  return null;
}

/** The reason in "Cancellation, clinic cancelled (clinician sick)". */
function reasonOf(message) {
  const m = /\(([^)]*)\)\s*$/.exec(message || '');
  return m ? m[1] : 'unexpected change';
}

/** Fills {placeholders}; unknown ones are left out rather than sent as "{name}". */
function fill(template, values) {
  return template.replace(/\{(\w+)\}/g, (_, k) => (values[k] === undefined || values[k] === null ? '' : String(values[k]))).replace(/\s+/g, ' ').trim();
}

// ---------------------------------------------------------------- phone numbers
/** A Canadian number in the form Twilio needs, "+16135551234", or null. */
function e164(phone) {
  if (!phone) return null;
  const digits = String(phone).replace(/\D/g, '');
  if (String(phone).trim().startsWith('+') && digits.length >= 10) return `+${digits}`;
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length === 11 && digits.startsWith('1')) return `+${digits}`;
  return null;
}

/** "•••1234", for the delivery log: staff see who it went to without the whole number. */
function masked(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  return digits.length >= 4 ? `•••${digits.slice(-4)}` : '';
}

// ---------------------------------------------------------------- the waitlist
/**
 * Who gets offered a freed time: someone waiting at this clinic whose days and part of the
 * day include it, who wants this clinician (or anyone), whose own visit is later, and who
 * doesn't already have an offer open. Priority first, then whoever joined first.
 */
function pickFromWaitlist(entries, freed, now = Date.now()) {
  const start = visitTime(freed.date, freed.minute);
  if (start <= now) return null;
  const day = weekday(freed.date), part = dayPart(freed.minute);
  const candidates = entries.filter((w) =>
    (w.days || []).includes(day)
    && (w.parts || []).includes(part)
    && (!w.clinicianId || w.clinicianId === freed.clinicianId)
    && w.date && typeof w.minute === 'number' && visitTime(w.date, w.minute) > start
    && !(w.offer && w.offer.expiresAt > now)
    && w.uid !== freed.patientUid);
  candidates.sort((a, b) => (a.priority === b.priority ? (a.joinedAt || 0) - (b.joinedAt || 0) : a.priority ? -1 : 1));
  return candidates[0] || null;
}

module.exports = {
  TIME_ZONE, PATIENT_APP, DEFAULT_TEMPLATES, LABELS,
  visitTime, clinicDate, weekday, dayPart, shortDate, formatTime,
  kindOf, reasonOf, fill, e164, masked, pickFromWaitlist,
};
