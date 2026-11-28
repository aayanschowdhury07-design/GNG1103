/// Not on the web: the staff app is a separate install.
/// Returns false when the staff app can't be opened from here.
bool openStaffApp() => false;

/// Not on the web: the privacy notice lives on the website, linked from the store listing.
const canOpenPrivacy = false;
void openPrivacy(String lang) {}
