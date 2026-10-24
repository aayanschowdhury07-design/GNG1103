import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'auth_screen.dart';
import 'firebase_options.dart';
import 'review.dart';
import 'shell.dart';
import 'wizard.dart';

/// Which Firebase the admin website uses, chosen when building or running:
///   (default)                    the local emulators (start them first)
///   --dart-define=BACKEND=live   the real project, clinicflow-9e598
/// and, for testing the seeded emulators at any hour:
///   --dart-define=SAMPLE_CLOCK=true    the day starts at 9:41 this morning
const backendChoice = String.fromEnvironment('BACKEND', defaultValue: 'emulator');
const sampleClock = bool.fromEnvironment('SAMPLE_CLOCK');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final clock = sampleClock ? ClinicClock.sampleMorning() : ClinicClock.real();
  final setup = backendChoice == 'live'
      ? await ClinicSetup.startProject(DefaultFirebaseOptions.currentPlatform, clock: clock)
      : await ClinicSetup.startEmulators(clock: clock);
  runApp(AdminApp(setup: setup));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key, required this.setup});
  final ClinicSetup setup;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClinicFlow for clinics',
      debugShowCheckedModeBanner: false,
      theme: clinicFlowTheme(Brightness.light),
      darkTheme: clinicFlowTheme(Brightness.dark),
      themeMode: ThemeMode.light, // light is the main look; dark comes with a toggle later
      home: ListenableBuilder(
        listenable: setup,
        builder: (context, _) {
          const wait = Scaffold(body: Center(child: CircularProgressIndicator()));
          if (setup.loading) return wait;
          if (!setup.signedIn) return AuthScreen(setup: setup);
          if (setup.platformAdmin) return ReviewScreen(setup: setup);
          if (setup.clinicId == null) return CreateClinicScreen(setup: setup);
          // the clinic and the person's staff record arrive a moment after the clinic is opened
          if (setup.clinic.isEmpty || setup.me == null || setup.desk == null) return wait;
          if (!setup.finished) return setup.me!.isAdmin ? WizardScreen(setup: setup) : NotReadyScreen(setup: setup);
          return StaffShell(setup: setup);
        },
      ),
    );
  }
}
