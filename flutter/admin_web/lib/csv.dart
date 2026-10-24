import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Downloads [rows] as a CSV file in the browser (the staff website is web-only).
void downloadCsv(String fileName, List<List<Object?>> rows) {
  final csv = rows.map((r) => r.map((v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"').join(',')).join('\r\n');
  final blob = web.Blob(['﻿$csv'.toJS].toJS, web.BlobPropertyBag(type: 'text/csv;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  (web.document.createElement('a') as web.HTMLAnchorElement)
    ..href = url
    ..download = fileName
    ..click();
  web.URL.revokeObjectURL(url);
}
