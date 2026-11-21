import 'package:web/web.dart' as web;

const _key = 'cf.role';

/// 'patient', 'staff', or null when this device hasn't chosen yet.
String? savedRole() {
  try {
    return web.window.localStorage.getItem(_key);
  } catch (_) {
    return null;
  }
}

void saveRole(String role) {
  try {
    web.window.localStorage.setItem(_key, role);
  } catch (_) {}
}

/// …/?start shows the first screen again, whatever was chosen before.
bool get forceChooser => Uri.base.queryParameters.containsKey('start');

/// Opens the staff app, which is served next to the patient app at …/staff/.
bool openStaffApp() {
  web.window.location.assign(Uri.base.resolve('staff/').toString());
  return true;
}
