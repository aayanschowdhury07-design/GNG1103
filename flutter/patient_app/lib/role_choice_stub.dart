/// Not on the web: nothing is remembered yet, and the staff app is a separate install.
String? savedRole() => null;
void saveRole(String role) {}
bool get forceChooser => false;

/// Returns false when the staff app can't be opened from here.
bool openStaffApp() => false;
