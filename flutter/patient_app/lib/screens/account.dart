import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scope.dart';
import '../widgets.dart';

/// Sign-in with a one-time code (no password to forget) or Face ID on a device that
/// has signed in before. Booking never needs an account, so that stays one tap away.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.onBookWithout});
  final VoidCallback onBookWithout;
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _who = TextEditingController(text: '+1 416 555 0142');
  final _code = TextEditingController();
  bool _codeSent = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _who.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final b = context.backend, who = _who.text.trim();
    if (!_codeSent) {
      if (who.replaceAll(RegExp(r'\D'), '').length < 10 && !who.contains('@')) {
        return setState(() => _error = 'Enter the mobile number or email you booked with.');
      }
      setState(() => _busy = true);
      try {
        await b.sendSignInCode(who);
      } catch (e) {
        debugPrint('sendSignInCode failed: $e');
        if (mounted) {
          setState(() {
            _busy = false;
            _error = "We couldn't send a code just now. Check your connection and try again.";
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _codeSent = true;
          _busy = false;
          _error = null;
        });
      }
      return;
    }
    setState(() => _busy = true);
    var ok = false;
    try {
      ok = await b.signIn(who, _code.text);
    } catch (e) {
      debugPrint('signIn failed: $e');
    }
    if (mounted && !ok) {
      setState(() {
        _busy = false;
        _error = "That code doesn't match. Check the message and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = context.backend is TestInbox ? context.backend as TestInbox : null;
    return ScreenFrame(
      back: false,
      title: 'Sign in',
      children: [
        Text('Sign in to see your visits, forms and receipts. Booking never needs an account.', style: context.text.bodySmall),
        const SizedBox(height: 16),
        TextField(
          controller: _who,
          enabled: !_codeSent,
          decoration: const InputDecoration(labelText: 'Mobile number or email'),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.email],
        ),
        if (_codeSent) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autofocus: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
            onSubmitted: (_) => _submit(),
          ),
          if (demo != null) _FromMessages(inbox: demo.inbox, onUse: (c) => _code.text = c),
        ],
        ErrorLine(_error),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_codeSent ? 'Sign in' : 'Send me a code')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => context.backend.signInWithDevice(), icon: const Icon(Icons.face_outlined), label: const Text('Use Face ID')),
        TextButton(onPressed: widget.onBookWithout, child: const Text('Book without signing in')),
      ],
    );
  }
}

/// The phone's own one-time-code suggestion, simulated from the demo inbox.
class _FromMessages extends StatelessWidget {
  const _FromMessages({required this.inbox, required this.onUse});
  final ValueNotifier<String?> inbox;
  final ValueChanged<String> onUse;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
        valueListenable: inbox,
        builder: (context, msg, _) {
          final code = RegExp(r'\d{6}').firstMatch(msg ?? '')?.group(0);
          return code == null
              ? const SizedBox.shrink()
              : Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => onUse(code), icon: const Icon(Icons.sms_outlined, size: 18), label: Text('From Messages: $code')));
        },
      );
}

/// People the patient books for. Reminders and offers for their visits come to this phone.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key, this.pickForBooking = false});

  /// Opened from "+ Add" while booking: the new person becomes who the visit is for.
  final bool pickForBooking;
  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _name = TextEditingController();
  String _relationship = 'Child';
  DateTime? _born;
  bool _permission = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Enter their full name.');
    if (!_permission) return setState(() => _error = 'Confirm you can book for them.');
    final f = await context.backend.addFamilyMember(name: name, relationship: _relationship, born: _born);
    if (!mounted) return;
    _name.clear();
    setState(() {
      _born = null;
      _permission = false;
      _error = null;
    });
    if (widget.pickForBooking) {
      context.draft.pickWho(f.name);
      Navigator.of(context).pop();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${f.name.split(' ').first} added')));
  }

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final family = context.backend.family();
      return ScreenFrame(
        title: 'Family members',
        children: [
          Text('Book and manage visits for people you care for. Reminders and waitlist offers for their visits come to your phone.', style: context.text.bodySmall),
          Section(
            child: Column(children: [
              if (family.isEmpty) Text('No one added yet.', style: context.text.bodySmall),
              for (final f in family)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(initials(f.name)),
                  title: Text(f.name),
                  subtitle: Text('${f.relationship} · born ${f.born == null ? 'not set' : MaterialLocalizations.of(context).formatMediumDate(f.born!)}'),
                ),
            ]),
          ),
          Section(
            title: 'Add someone',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 8),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name', hintText: 'e.g. Leela Raman'), textCapitalization: TextCapitalization.words),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _relationship,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Relationship'),
                items: [for (final r in const ['Child', 'Parent', 'Partner', 'Other']) DropdownMenuItem(value: r, child: Text(r))],
                onChanged: (v) => setState(() => _relationship = v!),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.cake_outlined, size: 18),
                label: Text(_born == null ? 'Date of birth' : 'Born ${MaterialLocalizations.of(context).formatMediumDate(_born!)}'),
                onPressed: () async {
                  final d = await showDatePicker(context: context, firstDate: DateTime(1920), lastDate: DateTime.now(), initialDate: DateTime(2015));
                  if (d != null) setState(() => _born = d);
                },
              ),
              CheckboxListTile(
                value: _permission,
                onChanged: (v) => setState(() => _permission = v!),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text("I'm their parent or guardian, or I have their permission to book for them.", style: context.text.bodySmall?.copyWith(color: context.colors.fg)),
              ),
              ErrorLine(_error),
              const SizedBox(height: 8),
              FilledButton(onPressed: _add, child: const Text('Add family member')),
            ]),
          ),
        ],
      );
    });
  }
}

/// Past visits at every clinic, with receipts and anything still owing.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, c = context.colors, owing = b.balanceOwing;
      void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      return ScreenFrame(
        title: 'Visit history',
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Balance owing', style: context.text.bodySmall),
                Text('\$${owing.toStringAsFixed(2)}', style: context.text.titleLarge?.copyWith(fontSize: 24, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
            if (owing > 0)
              FilledButton(onPressed: () async => snack('Paid \$${(await b.payBalance()).toStringAsFixed(2)}. Receipt emailed.'), child: const Text('Pay now'))
            else
              Text('All paid', style: context.text.labelLarge?.copyWith(color: c.good)),
          ]),
          Section(
            child: Column(children: [
              for (final v in b.visitHistory())
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.service),
                  subtitle: Text('${v.date} · ${v.clinician} · ${v.clinic}${v.who == context.session.name ? '' : ' · for ${v.who.split(' ').first}'}\n'
                      '${v.owing > 0 ? '\$${v.owing.toStringAsFixed(0)} owing' : 'Paid'}'),
                  isThreeLine: true,
                  trailing: TextButton(onPressed: () => snack('Receipt for ${v.date} emailed'), child: const Text('Receipt')),
                ),
            ]),
          ),
          Text("Receipts show the clinician's registration number so you can claim them with your insurer.", style: context.text.bodySmall),
        ],
      );
    });
  }
}
