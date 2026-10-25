import 'dart:async';

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'scope.dart';
import 'screens/account.dart';
import 'screens/booking.dart';
import 'screens/clinics.dart';
import 'screens/home.dart';
import 'screens/notifications.dart';
import 'screens/profile.dart';
import 'session.dart';

/// Which data the app runs on, chosen when building or running:
///   (default)                          sample data on the device, no server
///   --dart-define=BACKEND=emulator     the local Firebase emulators (start them and seed first)
///   --dart-define=BACKEND=live         the real Firebase project, clinicflow-9e598
/// and, for testing the seeded emulators at any hour:
///   --dart-define=SAMPLE_CLOCK=true    the day starts at 9:41 this morning (sample data always does)
const backendChoice = String.fromEnvironment('BACKEND', defaultValue: 'demo');
const sampleClock = bool.fromEnvironment('SAMPLE_CLOCK');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final clock = sampleClock ? ClinicClock.sampleMorning() : ClinicClock.real();
  final ClinicFlowBackend backend = switch (backendChoice) {
    'live' => await FirebaseBackend.startProject(DefaultFirebaseOptions.currentPlatform, clock: clock),
    'emulator' => await FirebaseBackend.startEmulators(clock: clock),
    _ => DemoBackend(),
  };
  runApp(PatientApp(backend: backend, session: PatientSession(), linkedClinic: linkedClinic()));
}

/// A clinic's booking link opens the app at …/c/{clinicId}: straight to booking there.
String? linkedClinic() {
  final p = Uri.base.pathSegments;
  return p.length >= 2 && p[0] == 'c' && p[1].isNotEmpty ? p[1] : null;
}

class PatientApp extends StatelessWidget {
  const PatientApp({super.key, required this.backend, required this.session, this.linkedClinic});
  final ClinicFlowBackend backend;
  final PatientSession session;

  /// Opened from a clinic's booking link.
  final String? linkedClinic;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      backend: backend,
      session: session,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) => MaterialApp(
          title: 'ClinicFlow',
          debugShowCheckedModeBanner: false,
          theme: clinicFlowTheme(Brightness.light),
          darkTheme: clinicFlowTheme(Brightness.dark),
          themeMode: session.themeMode,
          // the Large text setting scales every screen, on top of the phone's own text size
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: session.largeText ? 1.2 : 1,
            child: _DemoFrame(child: child!),
          ),
          home: Shell(linkedClinic: linkedClinic),
        ),
      ),
    );
  }
}

/// Home, Book, Clinics, Alerts and Profile tabs.
class Shell extends StatefulWidget {
  const Shell({super.key, this.linkedClinic});
  final String? linkedClinic;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  bool _started = false;

  // the Book tab is built on launch, so the booking draft needs a clinic before the first frame
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final b = context.backend, link = widget.linkedClinic;
    // a clinic's own link books there, even when it isn't listed in the directory (and if it
    // isn't taking bookings yet, the booking screen says so)
    if (link != null && _known(link)) {
      context.draft.start(b, link);
      _tab = 1;
    } else {
      context.draft.start(b, BookingDraft.defaultClinic(b));
    }
  }

  bool _known(String id) {
    try {
      context.backend.clinic(id);
      return true;
    } on StateError {
      return false; // not a clinic on ClinicFlow (or not yet): the app opens as usual
    }
  }

  void _go(int i) {
    final d = context.draft, b = context.backend;
    // Book starts fresh, at the clinic last chosen if it still takes bookings
    if (i == 1) d.start(b, d.clinicId.isNotEmpty && BookingDraft.canBook(b, b.clinic(d.clinicId)) ? d.clinicId : BookingDraft.defaultClinic(b), keepWho: '');
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      // booking and the directory work signed out; your visits, alerts and profile need sign-in
      final b = context.backend, s = context.s;
      Widget private(Widget screen) => b.signedIn ? screen : SignInScreen(onBookWithout: () => _go(1));
      final unread = b.pendingOffer() != null;
      return Scaffold(
        body: IndexedStack(index: _tab, children: [
          private(HomeScreen(onBook: () => _go(1), onClinics: () => _go(2))),
          const BookServiceScreen(embedded: true),
          const ClinicsScreen(),
          private(const NotificationsScreen()),
          private(const ProfileScreen()),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _go,
          destinations: [
            NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: s.t('navHome')),
            NavigationDestination(icon: const Icon(Icons.event_available_outlined), selectedIcon: const Icon(Icons.event_available), label: s.t('navBook')),
            NavigationDestination(icon: const Icon(Icons.map_outlined), selectedIcon: const Icon(Icons.map), label: s.t('navClinics')),
            NavigationDestination(
              icon: Badge(isLabelVisible: unread, label: const Text('1'), child: const Icon(Icons.notifications_outlined)),
              selectedIcon: const Icon(Icons.notifications),
              label: s.t('navAlerts'),
              tooltip: unread ? s.t('alertsOffer') : s.t('navAlerts'),
            ),
            NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: s.t('navProfile')),
          ],
        ),
      );
    });
  }
}

/// Demo only: on a wide screen the app sits in a phone-sized column, and texts the
/// sample backend "sends" appear as an incoming-message banner. Tap it to dismiss.
class _DemoFrame extends StatefulWidget {
  const _DemoFrame({required this.child});
  final Widget child;
  @override
  State<_DemoFrame> createState() => _DemoFrameState();
}

class _DemoFrameState extends State<_DemoFrame> {
  String? _msg;
  Timer? _hide;
  TestInbox? _demo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = context.backend;
    if (b is TestInbox && _demo == null) {
      _demo = (b as TestInbox)..inbox.addListener(_show);
    }
  }

  void _show() {
    setState(() => _msg = _demo!.inbox.value);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 6), () => mounted ? setState(() => _msg = null) : null);
  }

  @override
  void dispose() {
    _demo?.inbox.removeListener(_show);
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final app = Stack(children: [
      widget.child,
      if (_msg != null)
        Positioned(
          left: 12,
          right: 12,
          top: MediaQuery.paddingOf(context).top + 8,
          child: Semantics(
            liveRegion: true,
            child: Material(
              color: c.surface,
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _msg = null),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.s.t('msgBanner'), style: context.text.labelMedium?.copyWith(color: c.muted)),
                    const SizedBox(height: 2),
                    Text(_msg!, style: context.text.bodyMedium),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 600) return app;
      return ColoredBox(
        color: c.surface2,
        child: Center(
          child: Container(
            width: 412,
            height: box.maxHeight.clamp(0, 880),
            margin: const EdgeInsets.symmetric(vertical: 16),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: c.line),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 32, offset: const Offset(0, 12))],
            ),
            child: MediaQuery(data: MediaQuery.of(context).copyWith(size: Size(412, box.maxHeight.clamp(0, 880))), child: app),
          ),
        ),
      );
    });
  }
}
