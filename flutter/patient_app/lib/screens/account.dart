import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scope.dart';
import '../widgets.dart';

/// Sign-in with a one-time code by text (no password to forget). Booking never needs an
/// account, so that stays one tap away.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.onBookWithout});
  final VoidCallback onBookWithout;
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  // the test backends fill in the sample patient's number
  late final _who = TextEditingController(text: testInbox(context.backend) != null ? '+1 416 555 0142' : '');
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
    final b = context.backend, s = context.s, who = _who.text.trim();
    if (!_codeSent) {
      if (who.replaceAll(RegExp(r'\D'), '').length < 10) return setState(() => _error = s.t('errWho'));
      setState(() => _busy = true);
      try {
        await b.sendSignInCode(who);
      } catch (e) {
        debugPrint('sendSignInCode failed: $e');
        if (mounted) {
          setState(() {
            _busy = false;
            _error = s.t('errSend');
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
        _error = s.t('errSignInCode');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s, demo = testInbox(context.backend);
    return ScreenFrame(
      back: false,
      title: s.t('signInTitle'),
      actions: const [LangSwitch()],
      children: [
        Text(s.t('signInIntro'), style: context.text.bodySmall),
        const SizedBox(height: 16),
        TextField(
          controller: _who,
          enabled: !_codeSent,
          decoration: InputDecoration(labelText: s.t('phoneOnly')),
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
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
            decoration: InputDecoration(labelText: s.t('code'), counterText: ''),
            onSubmitted: (_) => _submit(),
          ),
          if (demo != null) _FromMessages(inbox: demo.inbox, onUse: (c) => _code.text = c),
        ],
        ErrorLine(_error),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(s.t(_codeSent ? 'signIn' : 'sendMeCode'))),
        const SizedBox(height: 8),
        // Face ID unlocks a sign-in saved on a phone; it arrives with the app-store version
        if (context.backend is DemoBackend)
          OutlinedButton.icon(onPressed: () => context.backend.signInWithDevice(), icon: const Icon(Icons.face_outlined), label: Text(s.t('faceId'))),
        TextButton(onPressed: widget.onBookWithout, child: Text(s.t('bookWithout'))),
      ],
    );
  }
}

/// The phone's own one-time-code suggestion, simulated from the test inbox.
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
              : Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(onPressed: () => onUse(code), icon: const Icon(Icons.sms_outlined, size: 18), label: Text(context.s.t('fromMessages', {'code': code}))),
                );
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
    final s = context.s, name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = s.t('errTheirName'));
    if (!_permission) return setState(() => _error = s.t('errPermission'));
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('added', {'name': f.name.split(' ').first}))));
  }

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final family = context.backend.family(), s = context.s;
      String date(DateTime d) => MaterialLocalizations.of(context).formatMediumDate(d);
      return ScreenFrame(
        title: s.t('family'),
        children: [
          Text(s.t('familyIntro'), style: context.text.bodySmall),
          Section(
            child: Column(children: [
              if (family.isEmpty) Align(alignment: Alignment.centerLeft, child: Text(s.t('noOne'), style: context.text.bodySmall)),
              for (final f in family)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(initials(f.name)),
                  title: Text(f.name),
                  subtitle: Text('${s.relationship(f.relationship)} · ${f.born == null ? s.t('bornUnknown') : s.t('bornOn', {'date': date(f.born!)})}'),
                ),
            ]),
          ),
          Section(
            title: s.t('addSomeoneTitle'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 8),
              TextField(controller: _name, decoration: InputDecoration(labelText: s.t('fullName')), textCapitalization: TextCapitalization.words),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _relationship,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.t('relationship')),
                items: [for (final r in const ['Child', 'Parent', 'Partner', 'Other']) DropdownMenuItem(value: r, child: Text(s.relationship(r)))],
                onChanged: (v) => setState(() => _relationship = v!),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.cake_outlined, size: 18),
                label: Text(_born == null ? s.t('dob') : s.t('bornLabel', {'date': date(_born!)})),
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
                title: Text(s.t('guardian'), style: context.text.bodySmall?.copyWith(color: context.colors.fg)),
              ),
              ErrorLine(_error),
              const SizedBox(height: 8),
              FilledButton(onPressed: _add, child: Text(s.t('addFamily'))),
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
      final b = context.backend, c = context.colors, s = context.s, owing = b.balanceOwing, me = myName(context);
      // paying and emailed receipts run on the sample data; the real ones come with payments
      final payments = b is DemoBackend;
      void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      final visits = b.visitHistory();
      return ScreenFrame(
        title: s.t('historyTitle'),
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('balance'), style: context.text.bodySmall),
                Text(s.money(owing), style: context.text.titleLarge?.copyWith(fontSize: 24, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
            if (owing > 0 && payments)
              FilledButton(onPressed: () async => snack(s.t('paidSnack', {'amount': s.money(await b.payBalance())})), child: Text(s.t('payNow')))
            else if (owing == 0)
              Text(s.t('allPaid'), style: context.text.labelLarge?.copyWith(color: c.good)),
          ]),
          if (owing > 0 && !payments) Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.t('payAtClinic'), style: context.text.bodySmall)),
          Section(
            child: Column(children: [
              if (visits.isEmpty) Align(alignment: Alignment.centerLeft, child: Text(s.t('noHistory'), style: context.text.bodySmall)),
              for (final v in visits)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.service),
                  subtitle: Text('${recordDate(v.date, lang: context.lang)} · ${v.clinician} · ${v.clinic}${v.who == me || v.who.isEmpty ? '' : ' · ${s.t('forName', {'name': v.who.split(' ').first})}'}\n'
                      '${v.owing > 0 ? s.t('owing', {'amount': s.money(v.owing)}) : s.t('paid')}'),
                  isThreeLine: true,
                  trailing: payments ? TextButton(onPressed: () => snack(s.t('receiptSnack', {'date': recordDate(v.date, lang: context.lang)})), child: Text(s.t('receipt'))) : null,
                ),
            ]),
          ),
          Text(s.t('insurer'), style: context.text.bodySmall),
        ],
      );
    });
  }
}
