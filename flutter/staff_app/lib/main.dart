import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'home.dart';
import 'patient_link.dart';
import 'l10n.dart';
import 'portal_theme.dart';

/// Which Firebase the staff app uses, chosen when building or running:
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
  runApp(StaffApp(setup: setup));
}

class StaffApp extends StatelessWidget {
  const StaffApp({super.key, required this.setup});
  final ClinicSetup setup;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: staffLang,
        builder: (context, code, _) => MaterialApp(
          locale: Locale(code, 'CA'),
          supportedLocales: const [Locale('en', 'CA'), Locale('fr', 'CA')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          title: 'ClinicFlow Staff',
          debugShowCheckedModeBanner: false,
          theme: staffPortalTheme().copyWith(
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: Colors.white,
              indicatorColor: portalColors.accentSoft,
              surfaceTintColor: Colors.transparent,
              height: 68,
              labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontSize: 12, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500, color: s.contains(WidgetState.selected) ? Portal.navy : portalColors.muted)),
              iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? Portal.navy : portalColors.muted)),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: Portal.navy, foregroundColor: Colors.white),
          ),
          // on a computer screen the app shows in a phone-sized frame, like the patient app
          builder: (context, child) => _PhoneFrame(child: child!),
          home: ListenableBuilder(
            listenable: setup,
            builder: (context, _) {
              const wait = Scaffold(body: Center(child: CircularProgressIndicator()));
              if (setup.loading) return wait;
              // a patient's phone sign-in on this device isn't a staff sign-in
              if (!setup.signedIn || (setup.user?.email ?? '').isEmpty) return SignInScreen(setup: setup);
              if (setup.platformAdmin) return _Notice(setup: setup, title: tr('Use the staff website'), text: tr('The ClinicFlow team reviews clinics on the staff website, not in the staff app.'));
              if (setup.clinicId == null) return _Notice(setup: setup, title: tr('No clinic yet'), text: tr('This account isn’t on a clinic’s team. Ask your clinic’s admin to invite you, or create your clinic on the staff website.'));
              if (setup.clinic.isEmpty || setup.me == null || setup.desk == null) return wait;
              if (!setup.finished) return _Notice(setup: setup, title: tr('Setup isn’t finished'), text: tr('Your clinic’s admin finishes setting up ClinicFlow on the staff website. The app works once that’s done.'));
              return StaffHome(setup: setup);
            },
          ),
        ),
      );
}

/// Sign-in for clinic staff: the same work email and password as the staff website.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.setup});
  final ClinicSetup setup;
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  String? _error;
  bool _busy = false, _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return setState(() => _error = tr('Enter your work email and password.'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.setup.signIn(_email.text, _password.text);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = switch (e.code) {
            'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-email' => tr('That email and password don’t match. Check them and try again.'),
            'too-many-requests' => tr('Too many tries. Wait a few minutes, then try again.'),
            'network-request-failed' => tr('No connection. Check your internet and try again.'),
            _ => tr('Couldn’t sign in: {why}', {'why': e.message ?? e.code}),
          });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Portal.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.spa_outlined, size: 44, color: Colors.white),
                const SizedBox(height: 10),
                Text('ClinicFlow', textAlign: TextAlign.center, style: Portal.serif(30, Colors.white)),
                const SizedBox(height: 6),
                Text(tr('Staff app').toUpperCase(), textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: Portal.sideInk, letterSpacing: 3.4)),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(tr('Sign in'), style: t.headlineSmall),
                      const SizedBox(height: 4),
                      Text(tr('Use the same work email and password as the staff website.'), style: t.bodySmall),
                      const SizedBox(height: 18),
                      TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: InputDecoration(labelText: tr('Work email'))),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: _hide,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _go(),
                        decoration: InputDecoration(
                          labelText: tr('Password'),
                          suffixIcon: IconButton(tooltip: _hide ? tr('Show password') : tr('Hide password'), icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide)),
                        ),
                      ),
                      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.crit))),
                      const SizedBox(height: 18),
                      FilledButton(onPressed: _busy ? null : _go, child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(tr('Sign in'))),
                      const SizedBox(height: 8),
                      Text(tr('Forgot your password? Reset it on the staff website.'), textAlign: TextAlign.center, style: t.bodySmall),
                    ]),
                  ),
                ),
                const SizedBox(height: 18),
                if (canOpenPatientApp)
                  Center(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      onPressed: openPatientApp,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: Text(tr('I’m a patient')),
                    ),
                  ),
                Center(
                  child: ValueListenableBuilder<String>(
                    valueListenable: staffLang,
                    builder: (context, code, _) => TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      onPressed: () => staffLang.value = code == 'en' ? 'fr' : 'en',
                      child: Text(code == 'en' ? 'Français' : 'English'),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.setup, required this.title, required this.text});
  final ClinicSetup setup;
  final String title, text;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(text, style: t.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 22),
              OutlinedButton(onPressed: setup.signOut, child: Text(tr('Sign out'))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Narrow screens get the app as it is; wider ones (a computer's browser) show it in a
/// phone-sized frame, so it looks and works the way it will on a phone.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 600) return child;
        final h = box.maxHeight.clamp(0.0, 880.0);
        return ColoredBox(
          color: const Color(0xFFE9EDF2),
          child: Center(
            child: Container(
              width: 412,
              height: h,
              margin: const EdgeInsets.symmetric(vertical: 16),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: portalColors.line),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .10), blurRadius: 32, offset: const Offset(0, 12))],
              ),
              child: MediaQuery(data: MediaQuery.of(context).copyWith(size: Size(412, h)), child: child),
            ),
          ),
        );
      });
}
