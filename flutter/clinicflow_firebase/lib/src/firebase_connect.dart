import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'saved_sign_in_stub.dart' if (dart.library.js_interop) 'saved_sign_in_web.dart';

/// Options for the local emulators. Project "demo-clinicflow" never reaches the cloud.
const emulatorOptions = FirebaseOptions(
  apiKey: 'demo-key',
  appId: '1:0:web:0',
  messagingSenderId: '0',
  projectId: 'demo-clinicflow',
  authDomain: 'demo-clinicflow.firebaseapp.com',
);

/// Starts Firebase once for the app: on the live project when [options] are given, otherwise
/// on the emulators at [emulatorHost].
Future<(FirebaseFirestore, FirebaseAuth)> connectFirebase({FirebaseOptions? options, String emulatorHost = 'localhost'}) async {
  if (options != null) {
    await Firebase.initializeApp(options: options);
    return (FirebaseFirestore.instance, FirebaseAuth.instance);
  }
  // see saved_sign_in_web.dart: on the web, forget the test sign-in so nothing reaches the real Firebase
  await clearSavedSignIn();
  await Firebase.initializeApp(options: emulatorOptions);
  final db = FirebaseFirestore.instance..useFirestoreEmulator(emulatorHost, 8080);
  final auth = FirebaseAuth.instance;
  await auth.useAuthEmulator(emulatorHost, 9099);
  return (db, auth);
}
