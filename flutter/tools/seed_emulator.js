// Fills the LOCAL Firebase emulators with the sample day, dated today: five directory clinics,
// their clinicians, services, unavailable time and bookings (plus a few earlier and later
// visits), Priya Raman's account, and Maple Grove's staff (one sign-in per role) for the
// staff website. The sample day is laid out from 9:00 am; build the apps with
// --dart-define=SAMPLE_CLOCK=true to start their clock at 9:41 am and see it as intended.
// It stands in for clinics finishing the setup wizard. It only talks to localhost and
// wipes the emulators first, so it's safe to re-run any time.
//
//   1. start the emulators (firebase emulators:start in the flutter folder)
//   2. node flutter/tools/seed_emulator.js
const PROJECT = 'demo-clinicflow';
const FS = `http://127.0.0.1:8080/v1/projects/${PROJECT}/databases/(default)/documents`;
const AUTH = 'http://127.0.0.1:9099';
const owner = { Authorization: 'Bearer owner', 'Content-Type': 'application/json' }; // emulator admin access

// ---- Firestore REST encoding
const val = (x) =>
  x === null || x === undefined ? { nullValue: null }
  : typeof x === 'boolean' ? { booleanValue: x }
  : Number.isInteger(x) ? { integerValue: String(x) }
  : typeof x === 'number' ? { doubleValue: x }
  : typeof x === 'string' ? { stringValue: x }
  : Array.isArray(x) ? { arrayValue: { values: x.map(val) } }
  : { mapValue: { fields: fields(x) } };
const fields = (o) => Object.fromEntries(Object.entries(o).map(([k, x]) => [k, val(x)]));
const writes = [];
const put = (path, data) => writes.push({ update: { name: `projects/${PROJECT}/databases/(default)/documents/${path}`, fields: fields(data) } });

// ---- dates: the sample day is today, on this computer's calendar
const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const at = (date) => new Date(`${date}T12:00:00`);
const TODAY = iso(new Date());
const addDays = (date, n) => { const d = at(date); d.setDate(d.getDate() + n); return iso(d); };
const weekday = (date) => ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][at(date).getDay()];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const shortDate = (date) => `${weekday(date)} ${MONTHS[at(date).getMonth()]} ${at(date).getDate()}`; // "Fri Oct 23"
const recordDate = (date) => `${MONTHS[at(date).getMonth()]} ${at(date).getDate()}, ${at(date).getFullYear()}`; // "Oct 23, 2026"
const daysAgo = (n) => Date.now() - n * 24 * 60 * 60 * 1000;
// whoever works on the sample day keeps working it, whatever weekday today is
const withToday = (days) => [...new Set([...days, weekday(TODAY)])];
const slot = (clinic, clinicianId, date, minute, appointmentId) =>
  put(`clinics/${clinic}/slots/${clinicianId}_${date}_${minute}`, { appointmentId, clinicianId, date, minute });

// ---- the sample day (the same data as DemoBackend in clinicflow_core)
const SLOTS = [540, 570, 600, 630, 660, 690, 780, 810, 840, 870, 900, 930, 960, 990];
const clinics = {
  mg: { initials: 'MG', name: 'Maple Grove Clinic', address: '214 Elm Ave', kind: 'Physiotherapy, chiropractic', lat: 43.6807, lng: -79.3838, accepting: true, isHome: true,
    notice: 'Parking lot B is closed this week. Street parking on Elm Ave is free for 2 hours.',
    // set up through the wizard, so the staff website opens straight onto the day
    city: 'Toronto, ON', phone: '+1 416 555 0100', brand: 'blue', languages: ['en', 'fr'], ready: true, listed: true, existing: 'fresh',
    rules: { cancelWindowHours: 24, offerHoldMinutes: 15, cutoffMinutes: 60, remind48: true, remind24: true },
    setup: { step: 8, done: [1, 2, 3, 4, 5, 6, 7, 8], startedAt: daysAgo(60), finishedAt: daysAgo(60) + 41 * 60 * 1000 } },
  df: { initials: 'DF', name: 'Dundas Family Health', address: '620 Bay St', kind: 'Family practice, walk-in', lat: 43.66, lng: -79.387, accepting: true },
  lp: { initials: 'LP', name: 'Lakeshore Physio', address: '45 St Clair Ave W', kind: 'Physiotherapy', lat: 43.6878, lng: -79.3985, accepting: true },
  qw: { initials: 'QW', name: 'Queen West Rehab', address: '215 Queen St W', kind: 'Rehab, massage', lat: 43.6505, lng: -79.3885, accepting: false },
  hm: { initials: 'HM', name: 'Harbour Mind Wellness', address: '25 Queens Quay E', kind: 'Mental health, counselling', lat: 43.6413, lng: -79.376, accepting: true },
};
const clinicians = {
  mg: { osei: ['Dr. Kwame Osei', 'Dr. Osei', 'Physiotherapist', 'Physiothérapeute'], lam: ['Mei Lam, PT', 'M. Lam', 'Physiotherapist', 'Physiothérapeute'], daoud: ['Dr. Rania Daoud', 'Dr. Daoud', 'Chiropractor', 'Chiropraticienne'] },
  df: { 'df-rahman': ['Dr. Aisha Rahman', 'Dr. Rahman', 'Family physician', 'Médecin de famille'], 'df-tran': ['Dr. Paul Tran', 'Dr. Tran', 'Family physician', 'Médecin de famille'] },
  lp: { 'lp-whitlock': ['Sam Whitlock, PT', 'S. Whitlock', 'Physiotherapist', 'Physiothérapeute'], 'lp-patel': ['Nora Patel, PT', 'N. Patel', 'Physiotherapist', 'Physiothérapeute'] },
  qw: { 'qw-moreau': ['Luc Moreau, RMT', 'L. Moreau', 'Massage therapist', 'Massothérapeute'] },
  hm: { 'hm-mensah': ['Grace Mensah, RP', 'G. Mensah', 'Psychotherapist', 'Psychothérapeute'] },
};
const services = {
  mg: {
    'mg-fu': ['Physiotherapy · follow-up', 'Physiothérapie · suivi', 'Physio follow-up', 30, 'Returning patients', 'Patients déjà suivis', ['osei', 'lam']],
    'mg-ia': ['Physiotherapy · initial assessment', 'Physiothérapie · évaluation initiale', 'Initial assessment', 45, 'New and returning', 'Nouveaux patients et patients suivis', ['osei', 'lam']],
    'mg-ch': ['Chiropractic · adjustment', 'Chiropratique · ajustement', 'Chiro adjustment', 20, 'New and returning', 'Nouveaux patients et patients suivis', ['daoud']],
  },
  df: {
    'df-rv': ['Family doctor · regular visit', 'Médecin de famille · visite régulière', 'Family doctor visit', 15, 'Registered and new patients', 'Patients inscrits et nouveaux patients', ['df-rahman', 'df-tran']],
    'df-rx': ['Prescription renewal', 'Renouvellement d’ordonnance', 'Prescription renewal', 15, 'Registered patients', 'Patients inscrits', ['df-rahman', 'df-tran']],
  },
  lp: {
    'lp-as': ['Physiotherapy · assessment', 'Physiothérapie · évaluation', 'Physio assessment', 45, 'New patients', 'Nouveaux patients', ['lp-whitlock', 'lp-patel']],
    'lp-tx': ['Physiotherapy · treatment', 'Physiothérapie · traitement', 'Physio treatment', 30, 'Returning patients', 'Patients déjà suivis', ['lp-whitlock', 'lp-patel']],
  },
  qw: { 'qw-ms': ['Massage therapy · 60 min', 'Massothérapie · 60 min', 'Massage', 60, 'Waitlist only', 'Liste d’attente seulement', ['qw-moreau']] },
  hm: { 'hm-cs': ['Counselling · first session', 'Counseling · première séance', 'Counselling, first session', 50, 'New clients', 'Nouveaux clients', ['hm-mensah']] },
};
const blocks = [
  ['mg', 'lam', 'Break', [660]], ['mg', 'lam', 'Not in', [840, 870, 900, 930, 960, 990]],
  ['mg', 'osei', 'Break', [780]], ['mg', 'daoud', 'Not in', null],
];
// Maple Grove's bookings: [patient, clinician, minute, service, status, formsDone, phone, ticket]
const mgAppts = [
  ['Priya Raman', 'osei', 540, 'mg-fu', 'booked', false, '0142'],
  ['Marcus Chen', 'osei', 570, 'mg-fu', 'late', true, '2201'],
  ['An Nguyen', 'lam', 540, 'mg-ia', 'inVisit', true, '6634', 'A-14'],
  ['Lucie Fortin', 'osei', 600, 'mg-fu', 'confirmed', true, '7788'],
  ['Raj Singh', 'lam', 600, 'mg-fu', 'booked', false, '5530'],
  ['Jordan Tremblay', 'osei', 660, 'mg-fu', 'confirmed', true, '4410'],
  ['Daniel Okafor', 'osei', 690, 'mg-fu', 'booked', true, '9921'],
  ['Tara Brown', 'lam', 690, 'mg-fu', 'confirmed', true, '3307'],
  ['Ella Moore', 'lam', 810, 'mg-ia', 'confirmed', false, '1185'],
  ['Hana Sato', 'osei', 840, 'mg-fu', 'confirmed', true, '2290'],
  ['Victor Diaz', 'osei', 900, 'mg-ia', 'booked', false, '6071'],
];
// the other clinics: everything is booked except these times
const open = { 'df-rahman': [960], 'df-tran': [960, 990], 'lp-whitlock': [690], 'lp-patel': [840, 870, 930], 'qw-moreau': [], 'hm-mensah': [780, 930] };
const PRIYA = 'priya-raman';

// Maple Grove's working days and hours, as the setup wizard records them
const mgHours = { osei: [withToday(['Mon', 'Tue', 'Wed', 'Thu', 'Fri']), 540, 1020], lam: [withToday(['Tue', 'Thu', 'Sat']), 540, 1020], daoud: [['Thu'], 540, 1020] };
const nextDayFor = (clin) => { let d = addDays(TODAY, 1); while (!mgHours[clin][0].includes(weekday(d))) d = addDays(d, 1); return d; };
// earlier today and earlier in the week: a cancellation (its time is free again), finished
// visits and missed ones, for the staff website's waitlist, missed-visits and reports pages
const mgEarlier = [
  // [id, patient, clinician, minute, service, status, date, extra]
  ['APT-20880', 'Omar Haddad', 'lam', 630, 'mg-fu', 'cancelled', TODAY, { phoneLast4: '4471' }],
  ['APT-20870', 'Kevin Park', 'osei', 600, 'mg-fu', 'noShow', addDays(TODAY, -1), { followUp: 'open', phoneLast4: '8812' }],
  ['APT-20871', 'Sofia Rossi', 'osei', 840, 'mg-ia', 'noShow', addDays(TODAY, -5), { followUp: 'contacted', phoneLast4: '3390' }],
  ['APT-20872', 'Grace Lee', 'osei', 540, 'mg-fu', 'complete', addDays(TODAY, -1), { checkedInAt: 532, waitingSince: 533, calledAt: 541 }],
  ['APT-20873', 'Ben Carter', 'osei', 570, 'mg-fu', 'complete', addDays(TODAY, -1), { checkedInAt: 566, waitingSince: 566, calledAt: 579 }],
  ['APT-20874', 'Mina Ahmadi', 'osei', 660, 'mg-ia', 'complete', addDays(TODAY, -1), { checkedInAt: 652, waitingSince: 653, calledAt: 662 }],
  ['APT-20875', 'Leo Martin', 'osei', 900, 'mg-fu', 'cancelled', addDays(TODAY, -1), {}],
];
// and the next days they work, so the week and month views have something on them
const mgLater = [
  // [id, patient, clinician, minute, service, status, date, phone]
  ['APT-20950', 'Noah Wilson', 'osei', 540, 'mg-fu', 'confirmed', nextDayFor('osei'), '5521'],
  ['APT-20951', 'Amira Hassan', 'osei', 600, 'mg-ia', 'booked', nextDayFor('osei'), '7734'],
  ['APT-20952', 'Chloe Martin', 'osei', 660, 'mg-fu', 'confirmed', nextDayFor('osei'), '1902'],
  ['APT-20953', 'Owen Clarke', 'lam', 570, 'mg-fu', 'booked', nextDayFor('lam'), '6658'],
];
// people waiting for an earlier time at Maple Grove: [uid, appointment, days, parts, preferred clinician, joined]
const mgWaitlist = [
  ['victor-diaz', 'APT-20911', withToday(['Mon', 'Tue', 'Wed']), ['morning'], null, daysAgo(3)],
  ['ella-moore', 'APT-20909', withToday(['Tue', 'Thu']), ['afternoon'], 'lam', daysAgo(2)],
];
// Maple Grove's team on the staff website, one account per role. The shared test password is
// for the local emulators only.
const STAFF_PASSWORD = 'maplegrove-test-1';
const mgStaff = [
  ['admin@maplegrove.test', 'Alex Moreau', 'admin', null],
  ['frontdesk@maplegrove.test', 'Nadia Karim', 'frontdesk', null],
  ['osei@maplegrove.test', 'Dr. Kwame Osei', 'clinician', 'osei'],
  ['support@maplegrove.test', 'Sam Patel', 'support', null],
];
// the ClinicFlow team, who approve new clinics (on the live project, added in the Firebase console)
const TEAM = ['team@clinicflow.test', 'ClinicFlow Team'];

// a clinic that just finished setup and is waiting for the team's review: not in the directory yet
const riverside = {
  initials: 'RP', name: 'Riverside Physio', address: '88 King St E', city: 'Toronto, ON', phone: '+1 416 555 0188', kind: 'Physiotherapy',
  lat: 43.6497, lng: -79.3744, accepting: true, brand: 'teal', languages: ['en'], ready: true, listed: true, existing: 'fresh',
  rules: { cancelWindowHours: 24, offerHoldMinutes: 15, cutoffMinutes: 60, remind48: true, remind24: true },
  setup: { step: 8, done: [1, 2, 3, 4, 5, 6, 7, 8], startedAt: Date.now() - 3 * 60 * 60 * 1000, finishedAt: Date.now() - 2 * 60 * 60 * 1000 },
  approval: 'pending', submittedAt: Date.now() - 2 * 60 * 60 * 1000,
};
const RIVERSIDE_OWNER = ['owner@riverside.test', 'Dana Whitfield'];
put('clinics/rv', riverside);
put('clinics/rv/clinicians/rv-shah', { name: 'Anika Shah, PT', short: 'A. Shah', role: 'Physiotherapist', days: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'], start: 540, end: 1020, addedAt: 0 });
put('clinics/rv/clinicians/rv-ortiz', { name: 'Ben Ortiz, PT', short: 'B. Ortiz', role: 'Physiotherapist', days: ['Mon', 'Wed', 'Fri'], start: 540, end: 1020, addedAt: 1 });
put('clinics/rv/services/rv-as', { name: 'Physiotherapy · assessment', nameFr: 'Physiothérapie · évaluation', short: 'Physio assessment', minutes: 45, online: true, clinicianIds: ['rv-shah', 'rv-ortiz'], order: 0 });
put('clinics/rv/services/rv-tx', { name: 'Physiotherapy · treatment', short: 'Physio treatment', minutes: 30, online: true, clinicianIds: ['rv-shah', 'rv-ortiz'], order: 1 });

for (const [id, c] of Object.entries(clinics)) {
  // the sample clinics were approved by the ClinicFlow team long ago
  put(`clinics/${id}`, { ...c, approval: 'approved', reviewedAt: daysAgo(58) });
  Object.entries(clinicians[id]).forEach(([cid, [name, short, role, roleFr]], i) => {
    const hours = id === 'mg' ? { days: mgHours[cid][0], start: mgHours[cid][1], end: mgHours[cid][2], addedAt: i } : {};
    put(`clinics/${id}/clinicians/${cid}`, { name, short, role, roleFr, ...hours });
  });
  Object.entries(services[id]).forEach(([sid, [name, nameFr, short, minutes, who, whoFr, clinicianIds]], order) => {
    put(`clinics/${id}/services/${sid}`, { name, nameFr, short, minutes, who, whoFr, clinicianIds, online: true, order });
  });
}
// the sample day's breaks and time off
blocks.forEach(([clinic, clinicianId, type, minutes], i) => put(`clinics/${clinic}/blocks/b${i}`, { clinicianId, type, minutes, date: TODAY }));
mgAppts.forEach(([patientName, clinicianId, minute, serviceId, status, formsDone, phoneLast4, ticket], i) => {
  const id = `APT-${20901 + i}`;
  put(`clinics/mg/appointments/${id}`, {
    clinicianId, minute, serviceId, patientName, status, formsDone, phoneLast4, date: TODAY,
    ...(ticket ? { ticket } : {}), ...(patientName === 'Priya Raman' ? { patientUid: PRIYA } : {}),
  });
  slot('mg', clinicianId, TODAY, minute, id);
});
for (const [clin, free] of Object.entries(open)) {
  const clinic = Object.keys(clinicians).find((c) => clinicians[c][clin]);
  for (const m of SLOTS.filter((m) => !free.includes(m))) slot(clinic, clin, TODAY, m, null);
}
// no slot documents for these: a cancelled time is free again, and past days need none
mgEarlier.forEach(([id, patientName, clinicianId, minute, serviceId, status, date, extra]) => {
  put(`clinics/mg/appointments/${id}`, { clinicianId, minute, serviceId, patientName, status, date, formsDone: true, ...extra });
});
mgLater.forEach(([id, patientName, clinicianId, minute, serviceId, status, date, phoneLast4]) => {
  put(`clinics/mg/appointments/${id}`, { clinicianId, minute, serviceId, patientName, status, date, phoneLast4, formsDone: status === 'confirmed' });
  slot('mg', clinicianId, date, minute, id);
});
mgWaitlist.forEach(([uid, appointmentId, days, parts, clinicianId, joinedAt]) => {
  const [patientName, , minute, serviceId] = mgAppts[Number(appointmentId.slice(4)) - 20901];
  put(`clinics/mg/waitlist/${uid}`, { uid, name: patientName, appointmentId, serviceId, date: TODAY, minute, days, parts, clinicianId, joinedAt, priority: false });
});
put('clinics/mg/invites/lam@maplegrove.test', { name: 'Mei Lam', email: 'lam@maplegrove.test', role: 'clinician', clinicianId: 'lam', clinicName: 'Maple Grove Clinic', invitedAt: daysAgo(4) });
// today's waiting-room queue: ticket numbers only, no names; numbers start over each day
put(`clinics/mg/queue/${TODAY}_A-14`, { ticket: 'A-14', n: 14, date: TODAY, clinicianId: 'lam', status: 'inVisit' });
put(`clinics/mg/queue/${TODAY}_A-13`, { ticket: 'A-13', n: 13, date: TODAY, clinicianId: 'walk', status: 'waiting' });
put(`clinics/mg/counters/tickets-${TODAY}`, { next: 15 });

// Priya's own records
put(`patients/${PRIYA}`, { name: 'Priya Raman', smsConsent: true, consentDate: recordDate(addDays(TODAY, -7)) });
put(`patients/${PRIYA}/family/f1`, { name: 'Arjun Raman', relationship: 'Child', born: '2017-04-12' });
[
  [`Booked: Physio, ${shortDate(TODAY)}, 9:00 am. Manage your visit any time from this link.`, `${recordDate(addDays(TODAY, -7))} · text and email`, 'update', null, 1],
  [`Reminder: Physio on ${shortDate(TODAY)} at 9:00 am with Dr. Osei.`, '2 days ago 9:00 am · push', 'reminder', null, 2],
  ['Please complete your reason-for-visit form before your visit.', 'Yesterday 9:01 am · text', 'todo', 'intake', 3],
  ['Reminder: Physio today 9:00 am with Dr. Osei. Tap to confirm.', 'Yesterday 9:00 am · push, then text', 'reminder', 'confirm', 4],
].forEach(([text, when, kind, action, n], i) => put(`patients/${PRIYA}/notices/n${i}`, { text, when, kind, action, at: n }));
[
  [14, 'Physiotherapy · follow-up', 'Dr. Kwame Osei', 'Maple Grove Clinic', 95, 0, 'Priya Raman'],
  [28, 'Physiotherapy · initial assessment', 'Dr. Kwame Osei', 'Maple Grove Clinic', 130, 40, 'Priya Raman'],
  [40, 'Chiropractic · adjustment', 'Dr. Rania Daoud', 'Maple Grove Clinic', 70, 0, 'Arjun Raman'],
  [110, 'Physiotherapy · follow-up', 'Sam Whitlock, PT', 'Lakeshore Physio', 90, 0, 'Priya Raman'],
].forEach(([ago, service, clinician, clinic, fee, owing, who], i) =>
  put(`patients/${PRIYA}/history/h${i}`, { date: recordDate(addDays(TODAY, -ago)), service, clinician, clinic, fee, owing, who, order: i }));

async function main() {
  const check = await fetch('http://127.0.0.1:8080/').catch(() => null);
  if (!check) throw new Error('The Firestore emulator is not running on port 8080. Start the emulators first.');
  // start clean
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  await fetch(`${AUTH}/emulator/v1/projects/${PROJECT}/accounts`, { method: 'DELETE' });
  // Priya signs in with her phone; her uid is fixed so her seeded visit is hers
  const user = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:batchCreate`, {
    method: 'POST', headers: owner,
    body: JSON.stringify({ users: [{ localId: PRIYA, phoneNumber: '+14165550142', displayName: 'Priya Raman' }] }),
  });
  if (!user.ok) throw new Error(`Creating the test patient failed: ${await user.text()}`);
  // staff accounts: email sign-ins with verified addresses
  const account = async (email, name) => {
    const res = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=x`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: STAFF_PASSWORD, displayName: name, returnSecureToken: true }),
    });
    const { localId } = await res.json();
    if (!localId) throw new Error(`Creating ${email} failed`);
    await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:update`, { method: 'POST', headers: owner, body: JSON.stringify({ localId, emailVerified: true }) });
    return localId;
  };
  const setOwner = (clinic, uid) => { writes.find((w) => w.update?.name.endsWith(`/documents/clinics/${clinic}`)).update.fields.ownerUid = val(uid); };
  // Maple Grove's team, and their staff records
  for (const [email, name, role, clinicianId] of mgStaff) {
    const localId = await account(email, name);
    put(`clinics/mg/staff/${localId}`, { uid: localId, name, email, role, clinicianId, clinicName: 'Maple Grove Clinic' });
    if (role === 'admin') setOwner('mg', localId);
  }
  // Riverside's owner, waiting for review
  const rvOwner = await account(...RIVERSIDE_OWNER);
  put(`clinics/rv/staff/${rvOwner}`, { uid: rvOwner, name: RIVERSIDE_OWNER[1], email: RIVERSIDE_OWNER[0], role: 'admin', clinicianId: null, clinicName: riverside.name });
  setOwner('rv', rvOwner);
  // the ClinicFlow team member who reviews it
  const team = await account(...TEAM);
  put(`platformAdmins/${team}`, { email: TEAM[0], name: TEAM[1] });
  for (let i = 0; i < writes.length; i += 400) {
    const res = await fetch(`${FS}:commit`, { method: 'POST', headers: owner, body: JSON.stringify({ writes: writes.slice(i, i + 400) }) });
    if (!res.ok) throw new Error(`Writing documents failed: ${await res.text()}`);
  }
  console.log(`Seeded ${writes.length} documents for the sample day, ${shortDate(TODAY)}: 1 patient (Priya Raman, +1 416 555 0142) and ${mgStaff.length} Maple Grove staff accounts.`);
  console.log(`Staff website sign-ins: ${mgStaff.map(([email, , role]) => `${email} (${role})`).join(', ')}, ${RIVERSIDE_OWNER[0]} (Riverside, waiting for review), ${TEAM[0]} (ClinicFlow team). Password: see STAFF_PASSWORD in this file.`);
}
main().catch((e) => { console.error(e.message); process.exit(1); });
