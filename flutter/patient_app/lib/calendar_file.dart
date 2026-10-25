// "Add to my calendar": a calendar file downloaded in the browser. On phones the app-store
// version will hand it to the phone's calendar instead (add_2_calendar or a share sheet).
export 'calendar_file_stub.dart' if (dart.library.js_interop) 'calendar_file_web.dart';
