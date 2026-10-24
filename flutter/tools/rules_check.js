// Checks firestore.rules on the LOCAL emulators before they're deployed: signs in as a guest,
// as Priya (seeded patient) and as a second patient, then tries what each should and shouldn't do.
//   node flutter/tools/seed_emulator.js && node flutter/tools/rules_check.js
const PROJECT = 'demo-clinicflow';
const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const DB = `projects/${PROJECT}/databases/(default)/documents`;
const FS = `http://127.0.0.1:8080/v1/${DB}`;

// the seed dates its sample day today, on this computer's calendar
const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const TODAY = iso(new Date());
const TOMORROW = iso(new Date(Date.now() + 24 * 60 * 60 * 1000));
// a time's document id: clinician, day and start minute
const key = (clinicianId, minute, date = TODAY) => `${clinicianId}_${date}_${minute}`;

const post = (url, body, token) =>
  fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });

async function guest() {
  const r = await (await post(`${AUTH}/accounts:signUp?key=x`, { returnSecureToken: true })).json();
  return { token: r.idToken, uid: r.localId };
}
async function phoneUser(phone) {
  const { sessionInfo } = await (await post(`${AUTH}/accounts:sendVerificationCode?key=x`, { phoneNumber: phone, recaptchaToken: 'x' })).json();
  const codes = (await (await fetch(`http://127.0.0.1:9099/emulator/v1/projects/${PROJECT}/verificationCodes`)).json()).verificationCodes;
  const code = codes.filter((c) => c.phoneNumber === phone).pop().code;
  const r = await (await post(`${AUTH}/accounts:signInWithPhoneNumber?key=x`, { sessionInfo, code })).json();
  return { token: r.idToken, uid: r.localId };
}

async function staffUser(email) {
  const r = await (await post(`${AUTH}/accounts:signUp?key=x`, { email, password: 'correct-horse-9', returnSecureToken: true })).json();
  return { token: r.idToken, uid: r.localId };
}
// Maple Grove's seeded staff (same password as STAFF_PASSWORD in seed_emulator.js)
async function seededStaff(email) {
  const r = await (await post(`${AUTH}/accounts:signInWithPassword?key=x`, { email, password: 'maplegrove-test-1', returnSecureToken: true })).json();
  if (!r.idToken) throw new Error(`Sign-in failed for ${email}. Run seed_emulator.js first.`);
  return { token: r.idToken, uid: r.localId };
}
async function verifyEmail(uid) {
  await fetch(`http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:update`, {
    method: 'POST', headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' }, body: JSON.stringify({ localId: uid, emailVerified: true }),
  });
}

// Firestore REST helpers
const val = (x) => (typeof x === 'string' ? { stringValue: x } : Number.isInteger(x) ? { integerValue: String(x) } : x === null ? { nullValue: null } : { booleanValue: x });
const fields = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, val(v)]));
const get = (path, token) => fetch(`${FS}/${path}`, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
const commit = (writes, token) => post(`${FS}:commit`, { writes }, token);
const create = (path, data) => ({ update: { name: `${DB}/${path}`, fields: fields(data) }, currentDocument: { exists: false } });
const update = (path, data) => ({ update: { name: `${DB}/${path}`, fields: fields(data) }, updateMask: { fieldPaths: Object.keys(data) } });
const del = (path) => ({ delete: `${DB}/${path}` });
// a create whose "at" field is set to the server's time, like FieldValue.serverTimestamp()
const createStamped = (path, data) => ({ ...create(path, data), updateTransforms: [{ fieldPath: 'at', setToServerValue: 'REQUEST_TIME' }] });
const myAppointments = (uid, token) =>
  post(`${FS}:runQuery`, { structuredQuery: { from: [{ collectionId: 'appointments', allDescendants: true }], where: { fieldFilter: { field: { fieldPath: 'patientUid' }, op: 'EQUAL', value: { stringValue: uid } } } } }, token);

let failures = 0;
async function expect(label, allowed, resPromise) {
  const res = await resPromise;
  const ok = allowed ? res.ok : res.status === 403;
  if (!ok) failures++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${allowed ? 'allowed' : 'denied '}  ${label}${ok ? '' : `  (got HTTP ${res.status}: ${(await res.text()).slice(0, 160)})`}`);
}

async function main() {
  const anon = await guest();
  const priya = await phoneUser('+14165550142');
  const other = await phoneUser('+14165550199');
  const later = Date.now() + 4 * 60 * 1000;
  const appt = { clinicianId: 'osei', serviceId: 'mg-fu', patientName: 'Priya Raman', minute: 960, status: 'confirmed', formsDone: false, date: TODAY };

  console.log('-- the directory is public, patient data is not');
  await expect('anyone reads a clinic', true, get('clinics/mg'));
  await expect('anyone reads which slots are taken', true, get(`clinics/mg/slots/${key('osei', 540)}`));
  await expect('a guest reads an appointment', false, get('clinics/mg/appointments/APT-20901', anon.token));
  await expect('Priya reads her own appointment', true, get('clinics/mg/appointments/APT-20901', priya.token));
  await expect("Priya reads someone else's appointment", false, get('clinics/mg/appointments/APT-20902', priya.token));
  await expect('Priya lists her appointments (collection group)', true, myAppointments(priya.uid, priya.token));
  await expect("another patient lists Priya's appointments", false, myAppointments(priya.uid, other.token));
  await expect("another patient reads Priya's profile", false, get(`patients/${priya.uid}`, other.token));
  await expect('a patient edits a clinic', false, commit([update('clinics/mg', { name: 'Hacked' })], priya.token));

  console.log('-- holds');
  await expect('a hold in someone else\'s name', false, commit([create(`clinics/mg/holds/${key('osei', 960)}`, { owner: 'x', holderUid: priya.uid, clinicianId: 'osei', date: TODAY, minute: 960, expiresAt: later })], anon.token));
  await expect('a guest holds 4:00 pm', true, commit([create(`clinics/mg/holds/${key('osei', 960)}`, { owner: 'x', holderUid: anon.uid, clinicianId: 'osei', date: TODAY, minute: 960, expiresAt: later })], anon.token));
  await expect('someone takes over a live hold', false, commit([update(`clinics/mg/holds/${key('osei', 960)}`, { holderUid: other.uid, owner: 'y', expiresAt: later })], other.token));
  await expect('a hold longer than 6 minutes', false, commit([create(`clinics/mg/holds/${key('osei', 990)}`, { owner: 'x', holderUid: other.uid, clinicianId: 'osei', date: TODAY, minute: 990, expiresAt: Date.now() + 60 * 60 * 1000 })], other.token));

  console.log('-- booking: slot + appointment + hold, all at once');
  await expect('a slot claimed without an appointment', false, commit([create(`clinics/mg/slots/${key('osei', 930)}`, { appointmentId: 'nope', clinicianId: 'osei', date: TODAY, minute: 930 })], priya.token));
  await expect('an appointment booked for someone else', false, commit([
    create('clinics/mg/appointments/X1', { ...appt, minute: 930, patientUid: other.uid }),
    create(`clinics/mg/slots/${key('osei', 930)}`, { appointmentId: 'X1', clinicianId: 'osei', date: TODAY, minute: 930 }),
  ], priya.token));
  await expect('Priya books 4:00 pm (uses the guest hold)', true, commit([
    create('clinics/mg/appointments/P1', { ...appt, patientUid: priya.uid }),
    create(`clinics/mg/slots/${key('osei', 960)}`, { appointmentId: 'P1', clinicianId: 'osei', date: TODAY, minute: 960 }),
    del(`clinics/mg/holds/${key('osei', 960)}`),
  ], priya.token));
  await expect('another patient books the same 4:00 pm', false, commit([
    create('clinics/mg/appointments/O1', { ...appt, patientUid: other.uid }),
    update(`clinics/mg/slots/${key('osei', 960)}`, { appointmentId: 'O1' }),
  ], other.token));
  await expect('a guest books (no verified phone)', false, commit([
    create('clinics/mg/appointments/G1', { ...appt, minute: 990, patientUid: 'guest' }),
    create(`clinics/mg/slots/${key('osei', 990)}`, { appointmentId: 'G1', clinicianId: 'osei', date: TODAY, minute: 990 }),
  ], anon.token));

  console.log('-- days: each day has its own times');
  await expect('the other patient books 4:00 pm tomorrow (same time, another day)', true, commit([
    create('clinics/mg/appointments/T1', { ...appt, date: TOMORROW, patientUid: other.uid }),
    create(`clinics/mg/slots/${key('osei', 960, TOMORROW)}`, { appointmentId: 'T1', clinicianId: 'osei', date: TOMORROW, minute: 960 }),
  ], other.token));
  await expect('a slot whose id leaves out the day', false, commit([
    create('clinics/mg/appointments/T2', { ...appt, date: TOMORROW, minute: 930, patientUid: other.uid }),
    create('clinics/mg/slots/osei_930', { appointmentId: 'T2', clinicianId: 'osei', date: TOMORROW, minute: 930 }),
  ], other.token));
  await expect('a slot filed under a different day than its booking', false, commit([
    create('clinics/mg/appointments/T3', { ...appt, date: TOMORROW, minute: 930, patientUid: other.uid }),
    create(`clinics/mg/slots/${key('osei', 930)}`, { appointmentId: 'T3', clinicianId: 'osei', date: TOMORROW, minute: 930 }),
  ], other.token));
  await expect('the other patient moves to 4:30 pm tomorrow', true, commit([
    create(`clinics/mg/slots/${key('osei', 990, TOMORROW)}`, { appointmentId: 'T1', clinicianId: 'osei', date: TOMORROW, minute: 990 }),
    del(`clinics/mg/slots/${key('osei', 960, TOMORROW)}`),
    update('clinics/mg/appointments/T1', { minute: 990 }),
  ], other.token));
  await expect('a queue entry filed without its day', false, commit([create('clinics/mg/queue/A-50', { ticket: 'A-50', n: 50, date: TODAY, clinicianId: 'osei', status: 'checkedIn' })], priya.token));

  console.log('-- changing a visit');
  await expect('Priya confirms her visit', true, commit([update('clinics/mg/appointments/APT-20901', { status: 'confirmed' })], priya.token));
  await expect('Priya marks herself complete', false, commit([update('clinics/mg/appointments/APT-20901', { status: 'complete' })], priya.token));
  await expect("another patient cancels Priya's visit", false, commit([update('clinics/mg/appointments/P1', { status: 'cancelled' })], other.token));
  await expect('Priya cancels 4:00 pm and frees the slot', true, commit([update('clinics/mg/appointments/P1', { status: 'cancelled' }), del(`clinics/mg/slots/${key('osei', 960)}`)], priya.token));
  await expect("another patient frees someone's slot", false, commit([del(`clinics/mg/slots/${key('osei', 540)}`)], other.token));

  console.log("-- Priya's own records");
  await expect('Priya marks her balance paid', true, commit([update(`patients/${priya.uid}/history/h1`, { owing: 0 })], priya.token));
  await expect('Priya changes a fee', false, commit([update(`patients/${priya.uid}/history/h1`, { fee: 1 })], priya.token));
  await expect('Priya creates her own waitlist offer', false, commit([create(`patients/${priya.uid}/offers/o1`, { minute: 630 })], priya.token));

  console.log('-- clinic setup (admin website)');
  const ownerEmail = `owner${Date.now()}@example.com`;
  const owner = await staffUser(ownerEmail);
  const outsider = await staffUser(`outsider${Date.now()}@example.com`);
  const cid = `test-clinic-${Date.now()}`;
  const newClinic = { name: 'Test Clinic', initials: 'TC', ownerUid: owner.uid, ready: false, listed: true, address: '', kind: '', approval: 'draft' };
  const makeClinic = (data) => commit([
    create(`clinics/${cid}`, data),
    create(`clinics/${cid}/staff/${owner.uid}`, { uid: owner.uid, role: 'admin', email: ownerEmail }),
  ], owner.token);
  await expect('a patient creates a clinic', false, commit([
    create(`clinics/${cid}`, { ...newClinic, ownerUid: priya.uid }),
    create(`clinics/${cid}/staff/${priya.uid}`, { uid: priya.uid, role: 'admin' }),
  ], priya.token));
  await expect('an account with an unconfirmed email creates a clinic', false, makeClinic(newClinic));
  await verifyEmail(owner.uid);
  owner.token = (await (await post(`${AUTH}/accounts:signInWithPassword?key=x`, { email: ownerEmail, password: 'correct-horse-9', returnSecureToken: true })).json()).idToken;
  await expect('a new clinic that starts out approved', false, makeClinic({ ...newClinic, approval: 'approved' }));
  await expect('a staff account creates a clinic without becoming its admin', false, commit([create(`clinics/${cid}`, newClinic)], owner.token));
  await expect('a verified account creates a clinic as its first admin', true, makeClinic(newClinic));
  await expect('the admin saves the clinic profile', true, commit([update(`clinics/${cid}`, { address: '1 Main St', kind: 'Physiotherapy' })], owner.token));
  await expect('the admin adds a service', true, commit([create(`clinics/${cid}/services/s1`, { name: 'Physio', minutes: 30, online: true })], owner.token));
  await expect('the admin hands the clinic to someone else', false, commit([update(`clinics/${cid}`, { ownerUid: outsider.uid })], owner.token));
  await expect('another staff account edits the clinic', false, commit([update(`clinics/${cid}`, { name: 'Taken' })], outsider.token));
  await expect('another staff account adds itself as admin', false, commit([create(`clinics/${cid}/staff/${outsider.uid}`, { uid: outsider.uid, role: 'admin' })], outsider.token));
  await expect('another staff account adds a service', false, commit([create(`clinics/${cid}/services/s2`, { name: 'Fake', minutes: 30 })], outsider.token));
  await expect('the admin invites a colleague', true, commit([create(`clinics/${cid}/invites/jo@example.com`, { name: 'Jo', email: 'jo@example.com', role: 'frontdesk' })], owner.token));
  await expect('another staff account reads the invitations', false, get(`clinics/${cid}/invites/jo@example.com`, outsider.token));
  await expect('the admin demotes themself', false, commit([update(`clinics/${cid}/staff/${owner.uid}`, { role: 'support' })], owner.token));
  await expect('the admin finds their clinic (collection group)', true, post(`${FS}:runQuery`, {
    structuredQuery: { from: [{ collectionId: 'staff', allDescendants: true }], where: { fieldFilter: { field: { fieldPath: 'uid' }, op: 'EQUAL', value: { stringValue: owner.uid } } } },
  }, owner.token));
  await expect("another staff account lists the owner's clinics", false, post(`${FS}:runQuery`, {
    structuredQuery: { from: [{ collectionId: 'staff', allDescendants: true }], where: { fieldFilter: { field: { fieldPath: 'uid' }, op: 'EQUAL', value: { stringValue: owner.uid } } } },
  }, outsider.token));
  await expect('the admin submits the finished clinic for review', true, commit([update(`clinics/${cid}`, { ready: true, approval: 'pending' })], owner.token));

  console.log('-- the ClinicFlow review (Riverside Physio, waiting)');
  const team = await seededStaff('team@clinicflow.test');
  const rvOwner = await seededStaff('owner@riverside.test');
  const mgAdmin = await seededStaff('admin@maplegrove.test');
  const review = (data, token) => commit([update('clinics/rv', data)], token);
  const rvBooking = (id, minute) => commit([
    create(`clinics/rv/appointments/${id}`, { ...appt, clinicianId: 'rv-shah', serviceId: 'rv-tx', minute, patientUid: priya.uid }),
    create(`clinics/rv/slots/${key('rv-shah', minute)}`, { appointmentId: id, clinicianId: 'rv-shah', date: TODAY, minute }),
  ], priya.token);
  await expect('Riverside approves itself', false, review({ approval: 'approved' }, rvOwner.token));
  await expect('Riverside writes its own review note', false, review({ approvalNote: 'All good' }, rvOwner.token));
  await expect('a patient books online at Riverside before it is approved', false, rvBooking('R1', 600));
  await expect('a team member reads their own team record', true, get(`platformAdmins/${team.uid}`, team.token));
  await expect("a clinic admin reads a team member's record", false, get(`platformAdmins/${team.uid}`, mgAdmin.token));
  await expect('someone adds themselves to the ClinicFlow team', false, commit([create(`platformAdmins/${outsider.uid}`, { email: 'x' })], outsider.token));
  await expect('the ClinicFlow team reads who set up Riverside', true, get(`clinics/rv/staff/${rvOwner.uid}`, team.token));
  await expect("another clinic's admin reads who set up Riverside", false, get(`clinics/rv/staff/${rvOwner.uid}`, mgAdmin.token));
  await expect('the ClinicFlow team renames Riverside', false, review({ name: 'Renamed' }, team.token));
  await expect('the ClinicFlow team sends Riverside back with a note', true, review({ approval: 'rejected', approvalNote: 'Phone did not answer.', reviewedAt: Date.now(), reviewedBy: team.uid }, team.token));
  await expect('Riverside fixes it and resubmits', true, review({ phone: '+1 416 555 0199', approval: 'pending' }, rvOwner.token));
  await expect("an approval signed with someone else's name", false, review({ approval: 'approved', reviewedAt: Date.now(), reviewedBy: rvOwner.uid }, team.token));
  await expect('the ClinicFlow team approves Riverside', true, review({ approval: 'approved', reviewedAt: Date.now(), reviewedBy: team.uid }, team.token));
  await expect('a patient books online at Riverside once approved', true, rvBooking('R2', 630));
  await expect('approved Riverside puts itself back to pending', false, review({ approval: 'pending' }, rvOwner.token));
  await expect('the ClinicFlow team queues the owner an email', true, commit([create('clinics/rv/outbox/r1', { by: team.uid, to: 'owner@riverside.test', message: 'Approved', status: 'queued' })], team.token));
  await expect('the ClinicFlow team records the decision in the audit log', true, commit([createStamped('clinics/rv/audit/r1', { actorUid: team.uid, action: 'clinic.approved' })], team.token));

  console.log('-- the staff website, by role (Maple Grove)');
  const admin = await seededStaff('admin@maplegrove.test');
  const desk = await seededStaff('frontdesk@maplegrove.test');
  const osei = await seededStaff('osei@maplegrove.test');
  const support = await seededStaff('support@maplegrove.test');
  await expect('the front desk reads any appointment', true, get('clinics/mg/appointments/APT-20904', desk.token));
  await expect('support reads an appointment', false, get('clinics/mg/appointments/APT-20904', support.token));
  await expect("Dr. Osei reads his own patient's appointment", true, get('clinics/mg/appointments/APT-20902', osei.token));
  await expect("Dr. Osei reads M. Lam's patient's appointment", false, get('clinics/mg/appointments/APT-20903', osei.token));
  await expect('a clinic\'s staff reads another clinic\'s appointment', false, get('clinics/mg/appointments/APT-20904', owner.token));
  await expect('the front desk moves a visit along', true, commit([update('clinics/mg/appointments/APT-20904', { status: 'waiting', waitingSince: 600 })], desk.token));
  await expect("the front desk changes a patient's name", false, commit([update('clinics/mg/appointments/APT-20904', { patientName: 'Someone Else' })], desk.token));
  await expect("Dr. Osei changes M. Lam's patient's status", false, commit([update('clinics/mg/appointments/APT-20903', { status: 'complete' })], osei.token));
  await expect('Dr. Osei calls in his own patient', true, commit([update('clinics/mg/appointments/APT-20904', { status: 'inVisit', calledAt: 610 })], osei.token));
  await expect('support marks a visit complete', false, commit([update('clinics/mg/appointments/APT-20904', { status: 'complete' })], support.token));
  const deskAppt = { ...appt, minute: 990, status: 'booked', patientUid: null, bookedBy: desk.uid, patientName: 'Phone Caller' };
  await expect('the front desk books a caller at 4:30 pm', true, commit([
    create('clinics/mg/appointments/D1', deskAppt),
    create(`clinics/mg/slots/${key('osei', 990)}`, { appointmentId: 'D1', clinicianId: 'osei', date: TODAY, minute: 990 }),
  ], desk.token));
  await expect('the front desk books the same 4:30 pm again (overwriting the slot)', false, commit([
    create('clinics/mg/appointments/D2', deskAppt),
    update(`clinics/mg/slots/${key('osei', 990)}`, { appointmentId: 'D2' }),
  ], desk.token));
  await expect('a front-desk booking marked confirmed for the patient', false, commit([
    create('clinics/mg/appointments/D3', { ...deskAppt, minute: 930, status: 'confirmed' }),
    create(`clinics/mg/slots/${key('osei', 930)}`, { appointmentId: 'D3', clinicianId: 'osei', date: TODAY, minute: 930 }),
  ], desk.token));
  await expect('support books a caller', false, commit([
    create('clinics/mg/appointments/D4', { ...deskAppt, minute: 930, bookedBy: support.uid }),
    create(`clinics/mg/slots/${key('osei', 930)}`, { appointmentId: 'D4', clinicianId: 'osei', date: TODAY, minute: 930 }),
  ], support.token));
  await expect('the front desk cancels and frees 4:30 pm', true, commit([update('clinics/mg/appointments/D1', { status: 'cancelled', cancelledBy: 'clinic' }), del(`clinics/mg/slots/${key('osei', 990)}`)], desk.token));

  console.log('-- waitlist offers');
  await expect('Priya joins the Maple Grove waitlist', true, commit([create(`clinics/mg/waitlist/${priya.uid}`, { uid: priya.uid, name: 'Priya Raman', minute: 540 })], priya.token));
  await expect('Priya puts someone else on the waitlist', false, commit([create(`clinics/mg/waitlist/${other.uid}`, { uid: other.uid, name: 'X' })], priya.token));
  await expect('a guest reads the waitlist', false, get(`clinics/mg/waitlist/${priya.uid}`, anon.token));
  await expect('the front desk flags Priya as priority', true, commit([update(`clinics/mg/waitlist/${priya.uid}`, { priority: true })], desk.token));
  await expect("the front desk edits Priya's waitlist times", false, commit([update(`clinics/mg/waitlist/${priya.uid}`, { minute: 1 })], desk.token));
  const offer = { clinicId: 'mg', clinicianId: 'lam', minute: 630, appointmentId: 'APT-20901', expiresAt: later };
  await expect('the front desk offers Priya a freed time', true, commit([create(`patients/${priya.uid}/offers/staff1`, offer)], desk.token));
  await expect('support offers Priya a freed time', false, commit([create(`patients/${priya.uid}/offers/staff2`, offer)], support.token));
  await expect('the front desk offers a time to someone not on the waitlist', false, commit([create(`patients/${other.uid}/offers/staff3`, offer)], desk.token));
  await expect("another clinic's admin offers Priya a Maple Grove time", false, commit([create(`patients/${priya.uid}/offers/staff4`, offer)], owner.token));

  console.log('-- messages and the audit log');
  await expect('the front desk queues a reminder', true, commit([create('clinics/mg/outbox/m1', { by: desk.uid, to: 'Raj Singh', message: 'Reminder', status: 'queued' })], desk.token));
  await expect('the front desk marks a message delivered', false, commit([update('clinics/mg/outbox/m1', { status: 'delivered' })], desk.token));
  await expect('support queues a message', false, commit([create('clinics/mg/outbox/m2', { by: support.uid, to: 'X', message: 'Hi', status: 'queued' })], support.token));
  await expect('the front desk records an action in the audit log', true, commit([createStamped('clinics/mg/audit/a1', { actorUid: desk.uid, action: 'test' })], desk.token));
  await expect('an audit entry in someone else\'s name', false, commit([createStamped('clinics/mg/audit/a2', { actorUid: admin.uid, action: 'test' })], desk.token));
  await expect('an audit entry with a made-up time', false, commit([create('clinics/mg/audit/a3', { actorUid: desk.uid, action: 'test', at: 1 })], desk.token));
  await expect('the admin edits the audit log', false, commit([update('clinics/mg/audit/a1', { action: 'changed' })], admin.token));
  await expect('the front desk reads the audit log', false, get('clinics/mg/audit/a1', desk.token));
  await expect('the admin reads the audit log', true, get('clinics/mg/audit/a1', admin.token));
  await expect('the front desk changes a colleague\'s role', false, commit([update(`clinics/mg/staff/${support.uid}`, { role: 'admin' })], desk.token));
  await expect('the front desk edits the clinic profile', false, commit([update('clinics/mg', { name: 'Renamed' })], desk.token));
  await expect('the admin posts an announcement', true, commit([update('clinics/mg', { notice: 'Closed Monday for the holiday.' })], admin.token));

  console.log('-- joining through an invitation (M. Lam, invited as a clinician)');
  const lam = await staffUser('lam@maplegrove.test');
  const join = (role, keepInvite) => commit([
    create(`clinics/mg/staff/${lam.uid}`, { uid: lam.uid, role, clinicianId: 'lam', email: 'lam@maplegrove.test' }),
    ...(keepInvite ? [] : [del('clinics/mg/invites/lam@maplegrove.test')]),
  ], lam.fresh ?? lam.token);
  await expect('an unverified account reads the invitation', false, get('clinics/mg/invites/lam@maplegrove.test', lam.token));
  await expect('an unverified account joins', false, join('clinician', false));
  await verifyEmail(lam.uid);
  lam.fresh = (await (await post(`${AUTH}/accounts:signInWithPassword?key=x`, { email: 'lam@maplegrove.test', password: 'correct-horse-9', returnSecureToken: true })).json()).idToken;
  await expect('the verified account reads its invitation', true, get('clinics/mg/invites/lam@maplegrove.test', lam.fresh));
  await expect('the verified account joins as admin instead', false, join('admin', false));
  await expect('the verified account joins but keeps the invitation', false, join('clinician', true));
  await expect('the verified account joins as invited', true, join('clinician', false));
  await expect('the new clinician reads her own patient', true, get('clinics/mg/appointments/APT-20903', lam.fresh));

  console.log(failures ? `\n${failures} check(s) FAILED` : '\nAll rule checks passed.');
  process.exit(failures ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(1); });
