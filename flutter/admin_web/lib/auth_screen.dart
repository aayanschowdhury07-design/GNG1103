import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'l10n.dart';

/// The privacy notice, on the patient site (it covers staff accounts too).
const privacyNoticeUrl = 'https://clinicflow-9e598.web.app/privacy/';

/// Staff sign-in, and sign-up for someone setting up a new clinic.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.setup});
  final ClinicSetup setup;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController(), _email = TextEditingController(), _password = TextEditingController();
  bool _creating = false, _busy = false;
  String? _error, _info;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  static String _message(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => tr('That email address doesn’t look right.'),
        'user-not-found' || 'wrong-password' || 'invalid-credential' => tr('Email or password is incorrect.'),
        'email-already-in-use' => tr('An account already uses this email. Sign in instead.'),
        'weak-password' => tr('Use a password of at least 8 characters.'),
        'too-many-requests' => tr('Too many attempts. Wait a few minutes and try again.'),
        'operation-not-allowed' => tr('Email sign-in isn’t turned on for this Firebase project yet.'),
        _ => tr('Something went wrong ({code}). Try again.', {'code': e.code}),
      };

  Future<void> _submit() async {
    final email = _email.text.trim(), password = _password.text;
    String? err;
    if (_creating && _name.text.trim().isEmpty) err = tr('Enter your name.');
    if (!email.contains('@')) err ??= tr('Enter your work email.');
    if (password.length < 8) err ??= tr('Use a password of at least 8 characters.');
    if (err != null) return setState(() => _error = err);
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      _creating ? await widget.setup.signUp(name: _name.text, email: email, password: password) : await widget.setup.signIn(email, password);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!_email.text.contains('@')) return setState(() => _error = tr('Enter your email first, then choose “Forgot password”.'));
    try {
      await widget.setup.sendPasswordReset(_email.text);
      setState(() {
        _info = tr('If an account uses {email}, a reset link is on its way.', {'email': _email.text.trim()});
        _error = null;
      });
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(8)),
                    child: Text('CF', style: t.titleMedium?.copyWith(color: c.heroFg)),
                  ),
                  const SizedBox(width: 12),
                  Text('ClinicFlow', style: t.headlineSmall),
                  const Spacer(),
                  const LangToggle(),
                ]),
                const SizedBox(height: 28),
                Text(_creating ? tr('Set up your clinic') : tr('Sign in to your clinic'), style: t.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  _creating ? tr('Create your admin account. Setup takes under an hour and needs no spreadsheets.') : tr('For clinic staff. Patients book through the ClinicFlow app or your booking link.'),
                  style: t.bodySmall,
                ),
                const SizedBox(height: 20),
                if (_creating) ...[
                  TextField(controller: _name, decoration: InputDecoration(labelText: tr('Your name')), autofillHints: const [AutofillHints.name], textInputAction: TextInputAction.next),
                  const SizedBox(height: 12),
                ],
                TextField(controller: _email, decoration: InputDecoration(labelText: tr('Work email')), keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], textInputAction: TextInputAction.next),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(labelText: tr('Password'), helperText: _creating ? tr('At least 8 characters') : null),
                  autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.crit, fontWeight: FontWeight.w500))),
                if (_info != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_info!, style: t.bodyMedium?.copyWith(color: c.good))),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _submit, child: Text(_creating ? tr('Create account') : tr('Sign in'))),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _creating = !_creating;
                      _error = null;
                      _info = null;
                    }),
                    child: Text(_creating ? tr('I already have an account') : tr('New clinic? Create an account')),
                  ),
                  if (!_creating) TextButton(onPressed: _reset, child: Text(tr('Forgot password'))),
                ]),
                Center(
                  child: TextButton(
                    onPressed: () => web.window.open('$privacyNoticeUrl?lang=$lang', '_blank'),
                    child: Text(tr('Privacy notice')),
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

/// The first thing a new admin does: name the clinic. That creates it, with them as its admin.
class CreateClinicScreen extends StatefulWidget {
  const CreateClinicScreen({super.key, required this.setup});
  final ClinicSetup setup;
  @override
  State<CreateClinicScreen> createState() => _CreateClinicScreenState();
}

class _CreateClinicScreenState extends State<CreateClinicScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error, _info;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 2) return setState(() => _error = tr('Enter your clinic’s name.'));
    setState(() => _busy = true);
    try {
      await widget.setup.createClinic(_name.text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('Couldn’t create the clinic: {error}', {'error': e});
        });
      }
    }
  }

  Future<void> _join(SetupInvite i) async {
    setState(() => _busy = true);
    try {
      await widget.setup.acceptInvite(i);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('Couldn’t join {clinic}: {error}', {'clinic': i.clinicName, 'error': e});
        });
      }
    }
  }

  Future<void> _verify({bool send = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (send) {
        await widget.setup.sendVerification();
        _info = tr('Verification link sent to {email}. Click it, then come back here.', {'email': widget.setup.user?.email});
      } else {
        await widget.setup.checkVerified();
        if (!widget.setup.emailVerified) _info = tr('Not verified yet. Click the link in the email first.');
      }
    } catch (e) {
      _error = tr('Something went wrong: {error}', {'error': e});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    final s = widget.setup, who = s.user?.displayName;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(who == null || who.isEmpty ? tr('Welcome') : tr('Welcome, {name}', {'name': who.split(' ').first}), style: t.headlineMedium),
              const SizedBox(height: 20),
              // a verified address comes first: for setting up a clinic and for joining one
              if (!s.emailVerified) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(tr('Confirm your email'), style: t.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      tr('We sent a link to {email}. Click it to confirm the address is yours, then come back here. '
                          'You need a confirmed address to set up a clinic or to join one.', {'email': s.user?.email}),
                      style: t.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton(onPressed: _busy ? null : _verify, child: Text(tr('I’ve clicked it'))),
                      TextButton(onPressed: _busy ? null : () => _verify(send: true), child: Text(tr('Send the link again'))),
                    ]),
                    if (_info != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_info!, style: t.bodySmall)),
                    if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: t.bodySmall?.copyWith(color: c.crit))),
                  ]),
                ),
                const SizedBox(height: 12),
                TextButton(onPressed: widget.setup.signOut, child: Text(tr('Sign out'))),
              ] else ...[
                // joining a clinic that invited you
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(tr('Joining your clinic?'), style: t.titleMedium),
                    const SizedBox(height: 4),
                    if (s.pendingInvites.isEmpty) ...[
                      Text(tr('No invitation for {email} yet. Ask your clinic’s admin to invite this address, then refresh.', {'email': s.user?.email}), style: t.bodySmall),
                      Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _busy ? null : _verify, child: Text(tr('Refresh')))),
                    ] else
                      for (final i in s.pendingInvites)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            Expanded(child: Text(i.clinicName.isEmpty ? tr('A clinic invited you as {role}.', {'role': tr(staffRoles[i.role] ?? i.role)}) : tr('{clinic} invited you as {role}.', {'clinic': i.clinicName, 'role': tr(staffRoles[i.role] ?? i.role)}), style: t.bodyMedium)),
                            const SizedBox(width: 12),
                            FilledButton(onPressed: _busy ? null : () => _join(i), child: Text(tr('Join'))),
                          ]),
                        ),
                    if (_info != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_info!, style: t.bodySmall?.copyWith(color: c.good))),
                  ]),
                ),
                const SizedBox(height: 28),
                Text(tr('Setting up a new clinic?'), style: t.titleMedium),
                const SizedBox(height: 4),
                Text(
                  tr('What is your clinic called? You’ll be its admin, and can invite your team in step 7. '
                      'When setup is done, ClinicFlow checks the clinic’s details before patients can find and book it, usually within one business day.'),
                  style: t.bodySmall,
                ),
                const SizedBox(height: 20),
                TextField(controller: _name, autofocus: true, decoration: InputDecoration(labelText: tr('Clinic name'), hintText: tr('e.g. Maple Grove Clinic')), onSubmitted: (_) => _create()),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.crit))),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _create, child: Text(tr('Start setup'))),
                TextButton(onPressed: widget.setup.signOut, child: Text(tr('Sign out'))),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// For staff who joined a clinic whose admin hasn't finished setup yet.
class NotReadyScreen extends StatelessWidget {
  const NotReadyScreen({super.key, required this.setup});
  final ClinicSetup setup;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('{clinic} isn’t set up yet', {'clinic': setup.clinic['name']}), style: t.headlineMedium),
              const SizedBox(height: 8),
              Text(tr('Your admin is still setting up the clinic. The calendar and queue open here as soon as they finish.'), style: t.bodyMedium),
              const SizedBox(height: 16),
              TextButton(onPressed: setup.signOut, child: Text(tr('Sign out'))),
            ]),
          ),
        ),
      ),
    );
  }
}
