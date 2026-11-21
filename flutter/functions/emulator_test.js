// Runs the Cloud Functions end to end on the LOCAL emulators (no real texts):
//   1. start: firebase emulators:start --only auth,firestore,functions (in the flutter folder)
//   2. node flutter/tools/seed_emulator.js
//   3. node flutter/functions/emulator_test.js
// It books, cancels and reminds at Maple Grove and checks what lands in the outbox.
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.GCLOUD_PROJECT = 'demo-clinicflow';
process.env.FUNCTIONS_EMULATOR = 'true';
const assert = require('assert');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const m = require('./messages');
if (!getApps().length) initializeApp({ projectId: 'demo-clinicflow' });
const db = getFirestore(), mg = db.doc('clinics/mg');
const PRIYA = 'priya-raman';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let n = 0;
const ok = (name) => { n++; console.log('PASS', name); };

/** Waits for an outbox entry for [appointmentId] of [kind] to be sent (or fail). */
async function sentFor(appointmentId, kind, timeout = 20000) {
  for (const end = Date.now() + timeout; Date.now() < end; await sleep(500)) {
    const q = await mg.collection('outbox').where('appointmentId', '==', appointmentId).get();
    const d = q.docs.map((x) => x.data()).find((x) => m.kindOf(x) === kind && x.status !== 'queued');
    if (d) return d;
  }
  throw new Error(`no ${kind} sent for ${appointmentId}`);
}

(async () => {
  const now = Date.now(), d3 = m.clinicDate(now, 3), d1 = m.clinicDate(now, 1);

  // 1. Priya books in the app, three days out: her confirmation goes to the phone she signed in with
  await mg.collection('slots').doc(`osei_${d3}_600`).set({ appointmentId: 'ft-priya', clinicianId: 'osei', date: d3, minute: 600 });
  await mg.collection('appointments').doc('ft-priya').set({ clinicianId: 'osei', serviceId: 'mg-fu', patientName: 'Priya Raman', patientUid: PRIYA, minute: 600, date: d3, status: 'confirmed', formsDone: false, phoneLast4: '0142' });
  const confirm = await sentFor('ft-priya', 'confirm');
  assert.strictEqual(confirm.status, 'sent (test)');
  assert.strictEqual(confirm.phone, '•••0142');
  assert.match(confirm.text, /^Hi Priya, you're booked: .+ on .+ at 10:00 am, Maple Grove/);
  ok(`app booking confirmed by text: "${confirm.text}"`);

  // 2. She joins the waitlist for anything earlier
  await mg.collection('waitlist').doc(PRIYA).set({ uid: PRIYA, name: 'Priya Raman', appointmentId: 'ft-priya', serviceId: 'mg-fu', date: d3, minute: 600, days: m.weekday(d1) ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] : [], parts: ['morning', 'afternoon', 'after4'], clinicianId: null, joinedAt: now, priority: false });

  // 3. Someone booked at the front desk for tomorrow 9:00 am cancels: the time is offered to Priya
  await mg.collection('slots').doc(`osei_${d1}_540`).set({ appointmentId: 'ft-desk', clinicianId: 'osei', date: d1, minute: 540 });
  await mg.collection('appointments').doc('ft-desk').set({ clinicianId: 'osei', serviceId: 'mg-fu', patientName: 'Sam Lee', patientUid: null, phone: '6135551234', phoneLast4: '1234', minute: 540, date: d1, status: 'booked', formsDone: false, bookedBy: 'desk' });
  await mg.collection('slots').doc(`osei_${d1}_540`).delete();
  await mg.collection('appointments').doc('ft-desk').update({ status: 'cancelled', cancelledBy: 'clinic' });
  const offer = await sentFor('ft-priya', 'offer');
  assert.strictEqual(offer.status, 'sent (test)');
  assert.match(offer.text, new RegExp(`${m.shortDate(d1)} at 9:00 am with .+ held for you for 15 minutes`));
  const offers = await db.collection(`patients/${PRIYA}/offers`).where('date', '==', d1).get();
  assert.strictEqual(offers.size, 1);
  assert.strictEqual((await mg.collection('waitlist').doc(PRIYA).get()).get('offer.minute'), 540);
  ok(`freed time offered to the waitlist: "${offer.text}"`);

  // 4. The front desk's own cancellation message (with its reason) reaches the number given at the desk
  await mg.collection('outbox').add({ at: new Date(), by: 'desk', to: 'Sam Lee', message: 'Cancellation, clinic cancelled (clinician sick)', channel: 'Text and email', appointmentId: 'ft-desk', status: 'queued' });
  const cancel = await sentFor('ft-desk', 'cancelClinic');
  assert.strictEqual(cancel.phone, '•••1234');
  assert.match(cancel.text, /\(clinician sick\)/);
  ok(`clinic cancellation texted to the desk number: "${cancel.text}"`);

  // 5. No consent, no text
  await db.doc(`patients/${PRIYA}`).update({ smsConsent: false });
  await mg.collection('outbox').add({ at: new Date(), by: 'desk', to: 'Priya Raman', message: 'Reminder, one-tap confirm', channel: 'Push, then text', appointmentId: 'ft-priya', status: 'queued' });
  const refused = await sentFor('ft-priya', 'reminder48');
  assert.strictEqual(refused.status, 'not sent');
  assert.strictEqual(refused.text, undefined);
  ok(`no text without consent: ${refused.note}`);
  await db.doc(`patients/${PRIYA}`).update({ smsConsent: true });

  // 6. Reminders: a visit about 47 hours away gets its 48 h reminder, once
  const at = now + 47 * 3600000, date = m.clinicDate(at);
  const minute = Math.round((at - m.visitTime(date, 0)) / 60000 / 15) * 15;
  await mg.collection('appointments').doc('ft-remind').set({ clinicianId: 'osei', serviceId: 'mg-fu', patientName: 'Priya Raman', patientUid: PRIYA, minute, date, status: 'confirmed', formsDone: false });
  await sentFor('ft-remind', 'confirm');
  const { sendReminders } = require('./index');
  await sendReminders.run({});
  const remind = await sentFor('ft-remind', 'reminder48');
  assert.strictEqual(remind.status, 'sent (test)');
  assert.strictEqual((await mg.collection('appointments').doc('ft-remind').get()).get('reminded48'), true);
  await sendReminders.run({});
  await sleep(3000);
  const again = (await mg.collection('outbox').where('appointmentId', '==', 'ft-remind').get()).docs.filter((d) => d.get('kind') === 'reminder48');
  assert.strictEqual(again.length, 1);
  ok(`48 h reminder sent once: "${remind.text}"`);

  console.log(`\n${n} end-to-end checks passed`);
  process.exit(0);
})().catch((e) => { console.error('FAIL', e.message); process.exit(1); });
