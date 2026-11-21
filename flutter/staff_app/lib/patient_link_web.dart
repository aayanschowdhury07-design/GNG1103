import 'package:web/web.dart' as web;

bool get canOpenPatientApp => true;

/// Back to the patient app, remembered as this device's choice.
void openPatientApp() {
  try {
    web.window.localStorage.setItem('cf.role', 'patient');
  } catch (_) {}
  web.window.location.assign(Uri.base.resolve('../').toString());
}
