import 'package:web/web.dart' as web;

bool get canOpenPatientApp => true;

/// Over to the patient app (served at /app; the site's root is the homepage).
void openPatientApp() {
  web.window.location.assign(Uri.base.resolve('/app').toString());
}

/// The privacy notice, served next to both apps at /privacy/; opens in a new tab.
void openPrivacy(String lang) {
  web.window.open(Uri.base.resolve('/privacy/?lang=$lang').toString(), '_blank');
}
