# ClinicFlow Flutter apps

| Folder | What it is |
|---|---|
| `clinicflow_core` | Shared by every app: data models, the backend interface (`ClinicFlowBackend`), booking rules, theme, English/French text, and `DemoBackend` (sample data, no server) |
| `clinicflow_firebase` | `FirebaseBackend`: the same interface on Firestore + Firebase Authentication; `ClinicSetup` and `ClinicDesk`, the staff website's side |
| `patient_app` | The patient app (Android, iOS, web) |
| `admin_web` | The staff website: setup wizard, dashboard, calendar, queue, check-in tablet, waitlist, missed visits, services, notifications, users, audit log, reports |
| `staff_app` | The staff app (not built yet) |
| `tools` | Scripts: start the Firebase emulators, fill them with sample data, serve a web build |

The screens only talk to `ClinicFlowBackend`, so they run unchanged on sample data or on Firebase.

## Run the patient app on sample data (no setup)

```
cd flutter/patient_app
flutter run -d edge
```

## Run it on Firebase, locally (the emulators)

Nothing here reaches the cloud: project `demo-clinicflow` exists only on this computer.
Needs the Firebase CLI (`npm install -g firebase-tools`) and Java 21.

1. Start the emulators and keep that terminal open (dashboard: http://localhost:4000):
   `node flutter/tools/start_emulators.js`
2. In another terminal, fill them with the sample day (re-run any time to start over):
   `node flutter/tools/seed_emulator.js`
3. Run the app against them (the security rules apply here too; check them with `node flutter/tools/rules_check.js`):
   `cd flutter/patient_app` then `flutter run -d edge --dart-define=BACKEND=emulator --dart-define=SAMPLE_CLOCK=true`

The apps run on the real date and time. The seed lays out a sample day dated today, from
9:00 am; `SAMPLE_CLOCK=true` starts the app's clock at 9:41 this morning so that day plays out
as intended at any hour. Leave it off to see the real time (most of today's sample visits will
then be in the past). Patients book up to two weeks ahead; staff book any day ahead.

Sign in as the sample patient with **+1 416 555 0142**. No text is sent: the code appears in the
app's "From Messages" button and in the emulator dashboard. On the web, every reload starts
signed out (on purpose, see `saved_sign_in_web.dart`).

## The staff website, on the emulators

`cd flutter/admin_web` then `flutter run -d edge` (it uses the emulators unless built with
`--dart-define=BACKEND=live`). The seed creates Maple Grove's team, one account per role:
`admin@`, `frontdesk@`, `osei@` (a clinician) and `support@maplegrove.test`, all with the test
password in `STAFF_PASSWORD` in `tools/seed_emulator.js`. Each role sees only its own pages, and the
security rules enforce the same limits. To try joining by invitation, create an account for
`lam@maplegrove.test` (invited as a clinician), verify the email (the link is printed in the emulator
terminal), then choose Join.

Messages (reminders, confirmations, offers) are queued in each clinic's `outbox` and listed in
Notifications → Delivery log; Cloud Functions will send them.

### Clinic review

A new clinic must confirm its owner's email, then finishes the setup wizard with "Submit for
review". It stays out of the patient directory, and patients can't book it online, until the
ClinicFlow team approves it; the security rules enforce this. Team members sign in to the same
staff website and land on the review page instead of a clinic. The seed has
`team@clinicflow.test` (team) and `owner@riverside.test` (Riverside Physio, waiting).

On the live project, team members can only be added from the Firebase console:
1. Create your account on the staff website and confirm your email.
2. Firebase console → Authentication → Users: copy your **User UID**.
3. Firestore Database → Start collection `platformAdmins` → Document ID: your User UID →
   field `email` (string) with your address → Save.
4. Sign out and back in to the staff website: you'll see the review page.

## Serve a web build without Flutter running

```
cd flutter/patient_app
flutter build web                                              # sample data
flutter build web --dart-define=BACKEND=emulator -o build/web_firebase
node ../tools/serve_web.js                                     # http://localhost:5180
node ../tools/serve_web.js patient 5181 web_firebase           # http://localhost:5181
node ../tools/serve_web.js admin 5182                          # staff website, after building in admin_web
```

## The live project: `clinicflow-9e598`

Firestore is in `northamerica-northeast2` (Toronto). The apps are registered and
`patient_app/lib/firebase_options.dart` holds their (public) Firebase settings.
Run against it with `flutter run -d edge --dart-define=BACKEND=live`.

`firestore.rules` and `firestore.indexes.json` are shared by the emulators and the live project.
Change them, run `node flutter/tools/rules_check.js` against the emulators, then deploy from `flutter/`:

```
firebase.cmd deploy --only firestore:rules,firestore:indexes --project clinicflow-9e598
```

Still to do before patients use it:
- Turn on Email/Password sign-in in the Firebase console, for the staff website.
- Cloud Functions: send the queued messages (texts, emails, push), make waitlist offers automatically,
  expire holds, and move booking there, so the rules tighten to match.
- The staff app (phone), on the same `ClinicDesk`.
- Time zones: dates and times follow the device's clock, which is right while clinics and
  patients are in the same zone. A clinic time zone setting comes before clinics outside Ontario.
- Opening hours that change week to week (different hours on different weeks) and services
  longer than one 30-minute slot taking up the slots after them.
