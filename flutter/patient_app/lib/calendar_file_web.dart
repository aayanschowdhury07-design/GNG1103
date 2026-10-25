import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Downloads [ics] as [fileName]; opening it adds the visit to the person's calendar.
bool saveCalendarFile(String fileName, String ics) {
  final url = web.URL.createObjectURL(web.Blob([ics.toJS].toJS, web.BlobPropertyBag(type: 'text/calendar;charset=utf-8')));
  (web.document.createElement('a') as web.HTMLAnchorElement)
    ..href = url
    ..download = fileName
    ..click();
  web.URL.revokeObjectURL(url);
  return true;
}
