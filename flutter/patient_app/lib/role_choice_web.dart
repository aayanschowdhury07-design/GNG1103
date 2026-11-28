import 'package:web/web.dart' as web;

/// Opens the staff app, which is served next to the patient app at /staff/.
bool openStaffApp() {
  web.window.location.assign(Uri.base.resolve('/staff/').toString());
  return true;
}

const canOpenPrivacy = true;

/// Opens the privacy notice (/privacy/) in a new tab, so a booking in progress isn't lost.
void openPrivacy(String lang) {
  web.window.open(Uri.base.resolve('/privacy/?lang=$lang').toString(), '_blank');
}
