// Checks the pure message logic: node test.js
const assert = require('assert');
const m = require('./messages');
let n = 0;
const check = (name, fn) => { fn(); n++; console.log('PASS', name); };

check('visit time in winter (EST, UTC-5)', () => assert.strictEqual(new Date(m.visitTime('2026-11-12', 600)).toISOString(), '2026-11-12T15:00:00.000Z'));
check('visit time in summer (EDT, UTC-4)', () => assert.strictEqual(new Date(m.visitTime('2026-07-02', 600)).toISOString(), '2026-07-02T14:00:00.000Z'));
check('visit time on the day the clocks go back', () => assert.strictEqual(new Date(m.visitTime('2026-11-01', 540)).toISOString(), '2026-11-01T14:00:00.000Z'));
check('clinic date late in the evening is still today', () => assert.strictEqual(m.clinicDate(Date.parse('2026-11-10T03:30:00Z')), '2026-11-09'));
check('clinic date plus days', () => assert.strictEqual(m.clinicDate(Date.parse('2026-11-30T15:00:00Z'), 2), '2026-12-02'));
check('weekday', () => assert.strictEqual(m.weekday('2026-11-09'), 'Mon'));
check('short date and time', () => assert.strictEqual(`${m.shortDate('2026-11-12')}, ${m.formatTime(810)}`, 'Thu Nov 12, 1:30 pm'));
check('noon and midnight', () => assert.deepStrictEqual([m.formatTime(720), m.formatTime(0)], ['12:00 pm', '12:00 am']));
check('day parts match the app', () => assert.deepStrictEqual([m.dayPart(719), m.dayPart(720), m.dayPart(960)], ['morning', 'afternoon', 'after4']));
check('phone numbers', () => assert.deepStrictEqual([m.e164('613 555 1234'), m.e164('16135551234'), m.e164('+1 (613) 555-1234'), m.e164('5551234')], ['+16135551234', '+16135551234', '+16135551234', null]));
check('masked number', () => assert.strictEqual(m.masked('+16135551234'), '•••1234'));
check('fill leaves no {holes}', () => assert.strictEqual(m.fill('Hi {first_name}, {missing} at {time}', { first_name: 'Priya', time: '9:00 am' }), 'Hi Priya, at 9:00 am'));
check('kind from staff labels', () => assert.deepStrictEqual(
  ['Booking confirmation', 'Cancellation, clinic cancelled (sick)', 'Reminder, one-tap confirm', 'Waitlist offer: Thu', 'Clinic approved'].map((message) => m.kindOf({ message })),
  ['confirm', 'cancelClinic', 'reminder48', 'offer', null]));
check('cancellation reason', () => assert.strictEqual(m.reasonOf('Cancellation, clinic cancelled (clinician sick)'), 'clinician sick'));
check('every default template fills completely', () => {
  const v = { first_name: 'Priya', service: 'Physio', clinician: 'Dr. Osei', clinic: 'Maple Grove', date: 'Thu Nov 12', time: '9:00 am', link: 'x', reason: 'sick', hold: 15 };
  for (const t of Object.values(m.DEFAULT_TEMPLATES)) assert.ok(!/[{}]/.test(m.fill(t, v)));
});

// the waitlist: a time freed on Thu Nov 12 at 10:00 am with Dr. Osei
const NOW = Date.parse('2026-11-09T15:00:00Z');
const freed = { clinicianId: 'osei', date: '2026-11-12', minute: 600, patientUid: 'canceller' };
const w = (uid, extra) => ({ uid, name: uid, days: ['Thu'], parts: ['morning'], clinicianId: null, date: '2026-11-20', minute: 600, joinedAt: 1, priority: false, ...extra });
const pick = (entries, f = freed) => (m.pickFromWaitlist(entries, f, NOW) || {}).uid;
check('waitlist: a match', () => assert.strictEqual(pick([w('a')]), 'a'));
check('waitlist: wrong day', () => assert.strictEqual(pick([w('a', { days: ['Fri'] })]), undefined));
check('waitlist: wrong part of the day', () => assert.strictEqual(pick([w('a', { parts: ['after4'] })]), undefined));
check('waitlist: wants another clinician', () => assert.strictEqual(pick([w('a', { clinicianId: 'lee' })]), undefined));
check('waitlist: their visit is already earlier', () => assert.strictEqual(pick([w('a', { date: '2026-11-11' })]), undefined));
check('waitlist: already has an open offer', () => assert.strictEqual(pick([w('a', { offer: { expiresAt: NOW + 60000 } })]), undefined));
check('waitlist: an expired offer doesn\'t count', () => assert.strictEqual(pick([w('a', { offer: { expiresAt: NOW - 60000 } })]), 'a'));
check('waitlist: never back to whoever cancelled', () => assert.strictEqual(pick([w('canceller')]), undefined));
check('waitlist: first to join goes first', () => assert.strictEqual(pick([w('late', { joinedAt: 9 }), w('early', { joinedAt: 2 })]), 'early'));
check('waitlist: priority beats joining order', () => assert.strictEqual(pick([w('early', { joinedAt: 2 }), w('flagged', { joinedAt: 9, priority: true })]), 'flagged'));
check('waitlist: a time already past is not offered', () => assert.strictEqual(pick([w('a')], { ...freed, date: '2026-11-08' }), undefined));

console.log(`\n${n} checks passed`);
