// ClinicFlow's Cloud Functions: the texts the apps can't send themselves.
//
//   sendQueued         every message goes through clinics/{clinic}/outbox: this sends each new
//                      one by text (Twilio) and records how it went, for the staff website's
//                      delivery log
//   bookingConfirmed   a patient booked in the app: queue their confirmation
//   visitCancelled     a time was freed: offer it to the next person on the clinic's waitlist
//   sendReminders      every 15 minutes: reminders 48 h and 24 h before each visit
//
// They run in Toronto, next to the database, so patient data stays in Canada. On the local
// emulators no text is sent: the message is written to the log instead.
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const { setGlobalOptions, logger } = require('firebase-functions/v2');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const m = require('./messages');

if (!getApps().length) initializeApp();
const db = getFirestore();
setGlobalOptions({ region: 'northamerica-northeast2', maxInstances: 5 });

const TWILIO_ACCOUNT_SID = defineSecret('TWILIO_ACCOUNT_SID');
const TWILIO_AUTH_TOKEN = defineSecret('TWILIO_AUTH_TOKEN');
const TWILIO_FROM_NUMBER = defineSecret('TWILIO_FROM_NUMBER');
const EMULATOR = process.env.FUNCTIONS_EMULATOR === 'true';
// Twilio's free trial only sends its own sample messages, named in the body (functions/.env).
// Until the account is upgraded, each text is the closest sample; our wording is kept in the
// delivery log. Set TWILIO_TRIAL=false after upgrading.
const TRIAL = process.env.TWILIO_TRIAL === 'true';
const TRIAL_SAMPLE = { offer: 'sms_event_notifications' }; // everything else: sms_appointment_reminders

// ---------------------------------------------------------------- sending
async function sendText(to, body, kind) {
  if (TRIAL) body = TRIAL_SAMPLE[kind] || 'sms_appointment_reminders';
  if (EMULATOR) {
    logger.info(`[test copy, not sent] to ${m.masked(to)}: ${body}`);
    return { sid: 'emulator' };
  }
  const sid = TWILIO_ACCOUNT_SID.value();
  const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
    method: 'POST',
    headers: {
      Authorization: 'Basic ' + Buffer.from(`${sid}:${TWILIO_AUTH_TOKEN.value()}`).toString('base64'),
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({ To: to, From: TWILIO_FROM_NUMBER.value(), Body: body }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Twilio ${json.code || res.status}: ${json.message || res.statusText}`);
  return { sid: json.sid };
}

/** The phone a visit's messages go to, and whether we may text it. */
async function recipient(appt) {
  // booked at the front desk: the number the patient gave there
  if (!appt.patientUid) return { phone: m.e164(appt.phone), consent: true };
  // booked in the app: the phone they signed in with, if they agreed to texts
  const [user, patient] = await Promise.all([
    getAuth().getUser(appt.patientUid).catch(() => null),
    db.doc(`patients/${appt.patientUid}`).get(),
  ]);
  return { phone: m.e164(user && user.phoneNumber), consent: patient.get('smsConsent') === true };
}

/** Everything a message's wording can mention about a visit. */
async function details(clinicRef, appt) {
  const [clinic, service, clinician] = await Promise.all([
    clinicRef.get(),
    appt.serviceId ? clinicRef.collection('services').doc(appt.serviceId).get() : null,
    appt.clinicianId ? clinicRef.collection('clinicians').doc(appt.clinicianId).get() : null,
  ]);
  return {
    clinic,
    values: {
      first_name: (appt.patientName || '').split(' ')[0] || 'there',
      service: (service && service.get('name')) || 'your visit',
      clinician: (clinician && (clinician.get('short') || clinician.get('name'))) || 'your clinician',
      clinic: clinic.get('name') || 'the clinic',
      date: appt.date ? m.shortDate(appt.date) : '',
      time: typeof appt.minute === 'number' ? m.formatTime(appt.minute) : '',
      link: m.PATIENT_APP,
    },
  };
}

/** The clinic's own wording for [kind], or ours. */
async function template(clinicRef, kind) {
  const t = await clinicRef.collection('templates').doc(kind).get();
  return (t.exists && t.get('en')) || m.DEFAULT_TEMPLATES[kind];
}

exports.sendQueued = onDocumentCreated(
  { document: 'clinics/{clinicId}/outbox/{id}', secrets: [TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER] },
  async (event) => {
    const ref = event.data.ref, entry = event.data.data();
    if (entry.status !== 'queued') return;
    const clinicRef = db.doc(`clinics/${event.params.clinicId}`);
    const done = (status, extra = {}) => ref.update({ status, sentAt: FieldValue.serverTimestamp(), ...extra });
    try {
      const kind = m.kindOf(entry);
      if (!kind || !entry.appointmentId) return done('not sent', { note: 'No text for this kind of message yet' });
      const appt = (await clinicRef.collection('appointments').doc(entry.appointmentId).get()).data();
      if (!appt) return done('not sent', { note: 'Visit not found' });
      // an offer is about the freed time, not the patient's own visit
      const about = kind === 'offer' && entry.offer ? { ...appt, ...entry.offer } : appt;
      const [{ phone, consent }, { values }, wording] = await Promise.all([recipient(appt), details(clinicRef, about), template(clinicRef, kind)]);
      if (!phone) return done('not sent', { note: 'No mobile number' });
      if (!consent) return done('not sent', { note: 'Patient said no to texts' });
      const body = m.fill(wording, { ...values, reason: m.reasonOf(entry.message), hold: entry.offer && entry.offer.holdMinutes });
      const { sid } = await sendText(phone, body, kind);
      await done(EMULATOR ? 'sent (test)' : 'sent', { text: body, phone: m.masked(phone), twilioSid: sid, channel: TRIAL ? 'Text (Twilio trial sample)' : 'Text' });
    } catch (e) {
      logger.error('message not sent', ref.path, e);
      await done('failed', { note: String(e.message || e).slice(0, 300) });
    }
  });

/** Queues a message: sendQueued picks it up. */
function queue(clinicRef, kind, appointmentId, to, extra = {}) {
  return clinicRef.collection('outbox').add({
    at: FieldValue.serverTimestamp(),
    by: 'clinicflow',
    to: to || '',
    message: m.LABELS[kind],
    kind,
    channel: 'Text',
    appointmentId,
    status: 'queued',
    ...extra,
  });
}

// ---------------------------------------------------------------- bookings
// Front-desk bookings already queue their confirmation from the staff website.
exports.bookingConfirmed = onDocumentCreated('clinics/{clinicId}/appointments/{id}', async (event) => {
  const appt = event.data.data();
  if (!appt.patientUid) return;
  await queue(db.doc(`clinics/${event.params.clinicId}`), 'confirm', event.params.id, appt.patientName);
});

// ---------------------------------------------------------------- the waitlist
exports.visitCancelled = onDocumentUpdated('clinics/{clinicId}/appointments/{id}', async (event) => {
  const before = event.data.before.data(), after = event.data.after.data();
  if (before.status === 'cancelled' || after.status !== 'cancelled') return;
  const clinicRef = db.doc(`clinics/${event.params.clinicId}`);
  const clinic = await clinicRef.get();
  if ((clinic.get('features') || {}).waitlist === false) return; // the clinic doesn't use the waitlist
  const freed = { clinicianId: before.clinicianId, date: before.date, minute: before.minute, patientUid: before.patientUid };
  const slotId = `${freed.clinicianId}_${freed.date}_${freed.minute}`;
  const holdMinutes = (clinic.get('rules') || {}).offerHoldMinutes || 15;

  const offered = await db.runTransaction(async (tx) => {
    const [slot, waitlist] = await Promise.all([tx.get(clinicRef.collection('slots').doc(slotId)), tx.get(clinicRef.collection('waitlist'))]);
    if (slot.exists) return null; // already booked again
    const w = m.pickFromWaitlist(waitlist.docs.map((d) => ({ uid: d.id, ...d.data() })), freed);
    if (!w) return null;
    const expiresAt = Date.now() + holdMinutes * 60 * 1000;
    const offer = { clinicianId: freed.clinicianId, date: freed.date, minute: freed.minute, expiresAt };
    // the same two records the front desk writes when it offers a time by hand
    tx.set(db.collection('patients').doc(w.uid).collection('offers').doc(), { clinicId: clinicRef.id, appointmentId: w.appointmentId, by: 'clinicflow', ...offer });
    tx.update(clinicRef.collection('waitlist').doc(w.uid), { offer });
    return { w, offer };
  });
  if (!offered) return;
  const { w, offer } = offered, when = `${m.shortDate(offer.date)}, ${m.formatTime(offer.minute)}`;
  await Promise.all([
    queue(clinicRef, 'offer', w.appointmentId, w.name, { offer: { clinicianId: offer.clinicianId, date: offer.date, minute: offer.minute, holdMinutes }, message: `Waitlist offer: ${when}` }),
    clinicRef.collection('audit').add({
      at: FieldValue.serverTimestamp(), actorUid: 'clinicflow', actor: 'ClinicFlow (automatic)',
      action: 'waitlist.offer', record: w.uid, detail: `${w.name} · ${when} · held ${holdMinutes} min`,
    }),
  ]);
});

// ---------------------------------------------------------------- reminders
// Each reminder goes out once, in a 4-hour window before the 48 h or 24 h mark, so a visit
// booked the day before doesn't get a "reminder" right after its confirmation.
const WINDOW_HOURS = 4;

exports.sendReminders = onSchedule({ schedule: 'every 15 minutes', timeZone: m.TIME_ZONE }, async () => {
  const now = Date.now();
  const dates = [0, 1, 2, 3].map((d) => m.clinicDate(now, d));
  const visits = await db.collectionGroup('appointments').where('date', 'in', dates).get();
  const clinics = new Map();
  let sent = 0;
  for (const doc of visits.docs) {
    const a = doc.data();
    if (!['booked', 'confirmed'].includes(a.status)) continue;
    const hours = (m.visitTime(a.date, a.minute) - now) / 3600000;
    const clinicRef = doc.ref.parent.parent;
    if (!clinics.has(clinicRef.id)) clinics.set(clinicRef.id, (await clinicRef.get()).get('rules') || {});
    const rules = clinics.get(clinicRef.id);
    let kind = null;
    if (!a.reminded24 && rules.remind24 !== false && hours <= 24 && hours > 24 - WINDOW_HOURS) kind = 'reminder24';
    else if (!a.reminded48 && rules.remind48 !== false && hours <= 48 && hours > 48 - WINDOW_HOURS) kind = 'reminder48';
    if (!kind) continue;
    await doc.ref.update(kind === 'reminder24' ? { reminded24: true, reminded48: true } : { reminded48: true });
    await queue(clinicRef, kind, doc.id, a.patientName);
    sent++;
  }
  logger.info(`reminders queued: ${sent} of ${visits.size} visits checked`);
});
