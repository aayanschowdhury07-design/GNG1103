import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Emulator testing on the web only: forget the saved test sign-in before Firebase starts.
/// Otherwise the SDK restores it with a network call before the emulator is connected and
/// later calls go to the real Firebase. Every reload therefore starts signed out.
Future<void> clearSavedSignIn() async {
  final done = Completer<void>();
  void finish(web.Event _) {
    if (!done.isCompleted) done.complete();
  }

  final request = web.window.indexedDB.deleteDatabase('firebaseLocalStorageDb');
  request.onsuccess = finish.toJS;
  request.onerror = finish.toJS;
  request.onblocked = finish.toJS;
  await done.future.timeout(const Duration(seconds: 2), onTimeout: () {});
}
