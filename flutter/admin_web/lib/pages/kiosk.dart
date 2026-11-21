import 'dart:async';

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../kiosk_lock.dart';
import '../l10n.dart';
import '../visit.dart';

const _words = {
  'en': {
    'welcome': 'Welcome to {clinic}',
    'intro': 'Enter the last 4 digits of your phone number to check in.',
    'continue': 'Continue',
    'clear': 'Clear',
    'delete': 'Delete',
    'need4': 'Enter all 4 digits.',
    'none': 'We couldn’t find a visit today for that number. Please see the front desk.',
    'isYou': 'Is this you?',
    'with': '{time} with {who}',
    'notMe': 'That’s not me',
    'privacy': 'Only initials are shown, for your privacy.',
    'done': 'You’re checked in',
    'ticket': 'Your ticket number. Have a seat; it will show on the screen when it’s your turn.',
    'finish': 'Done',
    'failed': 'Check-in didn’t go through. Please see the front desk.',
    'digits': '{n} of 4 digits entered',
  },
  'fr': {
    'welcome': 'Bienvenue à {clinic}',
    'intro': 'Entrez les 4 derniers chiffres de votre numéro de téléphone pour vous enregistrer.',
    'continue': 'Continuer',
    'clear': 'Effacer',
    'delete': 'Supprimer',
    'need4': 'Entrez les 4 chiffres.',
    'none': 'Aucun rendez-vous aujourd’hui pour ce numéro. Veuillez vous adresser à l’accueil.',
    'isYou': 'Est-ce vous?',
    'with': '{time} avec {who}',
    'notMe': 'Ce n’est pas moi',
    'privacy': 'Seules les initiales sont affichées, pour votre confidentialité.',
    'done': 'Vous êtes enregistré',
    'ticket': 'Votre numéro. Asseyez-vous; il s’affichera à l’écran quand ce sera votre tour.',
    'finish': 'Terminé',
    'failed': 'L’enregistrement n’a pas fonctionné. Veuillez vous adresser à l’accueil.',
    'digits': '{n} chiffres sur 4 saisis',
  },
};

/// The front-desk tablet patients check themselves in on. Tap or type; the language and the
/// digits reset after each patient, so the next one starts fresh.
///
/// Staff open it with the tablet PIN, then press Full screen: the staff website disappears and
/// only check-in is left until someone enters the PIN again, even after a reload or Esc.
class KioskPage extends StatefulWidget {
  const KioskPage({super.key, required this.setup, required this.desk, this.locked = false, this.onLock, this.onUnlock});
  final ClinicSetup setup;
  final ClinicDesk desk;

  /// Running as the locked, full-screen tablet (no staff website around it).
  final bool locked;
  final VoidCallback? onLock, onUnlock;
  @override
  State<KioskPage> createState() => _KioskPageState();
}

class _KioskPageState extends State<KioskPage> {
  String _lang = 'en', _digits = '';
  String? _error, _ticket;
  List<DeskAppt>? _matches;
  bool _busy = false;
  Timer? _reset;
  final _focus = FocusNode();

  /// The PIN was entered on this visit to the page (always true once locked).
  bool _unlocked = false;
  late Future<bool> _pinSet = widget.desk.kioskPinSet();
  void Function()? _unlisten;

  @override
  void initState() {
    super.initState();
    _unlisten = KioskLock.onFullscreenChange(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _askToExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: PinEntry(
              desk: widget.desk,
              title: tr('Staff only'),
              note: tr('Enter the tablet PIN to leave check-in mode.'),
              onOk: () => Navigator.pop(context, true),
              onCancel: () => Navigator.pop(context, false),
            ),
          ),
        ),
      ),
    );
    if (ok == true) widget.onUnlock?.call();
  }

  String w(String k, [Map<String, String> v = const {}]) => v.entries.fold(_words[_lang]![k]!, (s, e) => s.replaceAll('{${e.key}}', e.value));

  @override
  void dispose() {
    _unlisten?.call();
    _reset?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _key(String k) {
    if (_matches != null || _ticket != null) return;
    setState(() {
      if (k == 'del') {
        if (_digits.isNotEmpty) _digits = _digits.substring(0, _digits.length - 1);
      } else if (k == 'clr') {
        _digits = '';
      } else if (_digits.length < 4) {
        _digits += k;
      }
      _error = null;
    });
  }

  void _find() {
    if (_digits.length < 4) return setState(() => _error = w('need4'));
    final m = widget.desk.findForCheckIn(_digits);
    setState(() => m.isEmpty ? _error = w('none') : _matches = m);
  }

  Future<void> _checkIn(DeskAppt a) async {
    setState(() => _busy = true);
    try {
      final t = await widget.desk.setStatus(a, ApptStatus.checkedIn);
      setState(() {
        _ticket = t;
        _matches = null;
      });
      _reset = Timer(const Duration(seconds: 8), _start);
    } catch (e) {
      setState(() => _error = w('failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _start() {
    _reset?.cancel();
    if (!mounted) return;
    setState(() {
      _lang = 'en';
      _digits = '';
      _error = null;
      _ticket = null;
      _matches = null;
    });
    _focus.requestFocus();
  }

  static String _initials(String name) => name.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).map((x) => '${x[0].toUpperCase()}.').join(' ');

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final body = _ticket != null
        ? Column(mainAxisSize: MainAxisSize.min, children: [
            Text(w('done'), style: t.headlineMedium, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Text(_ticket!, style: TextStyle(fontSize: 72, fontWeight: FontWeight.w700, color: c.accent)),
            const SizedBox(height: 8),
            Text(w('ticket'), style: t.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _start, child: Text(w('finish')))),
          ])
        : _matches != null
            ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(w('isYou'), style: t.headlineMedium),
                const SizedBox(height: 16),
                for (final a in _matches!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16), alignment: Alignment.centerLeft),
                      onPressed: _busy ? null : () => _checkIn(a),
                      child: Row(children: [
                        CircleAvatar(backgroundColor: c.accentSoft, child: Text(_initials(a.patientName).replaceAll('.', '').replaceAll(' ', ''), style: TextStyle(color: c.accent))),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_initials(a.patientName), style: t.titleMedium),
                          Text(w('with', {'time': formatTime(a.minute, lang: _lang), 'who': clinicianShort(widget.setup, a.clinicianId)}), style: t.bodySmall),
                        ]),
                      ]),
                    ),
                  ),
                TextButton(onPressed: _start, child: Text(w('notMe'))),
                Text(w('privacy'), style: t.bodySmall, textAlign: TextAlign.center),
              ])
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'fr', label: Text('Français'))],
                    selected: {_lang},
                    onSelectionChanged: (v) => setState(() => _lang = v.first),
                  ),
                ),
                const SizedBox(height: 12),
                Text(w('welcome', {'clinic': widget.setup.clinic['name'] ?? ''}), style: t.headlineMedium),
                const SizedBox(height: 6),
                Text(w('intro'), style: t.bodyMedium?.copyWith(color: c.muted)),
                const SizedBox(height: 20),
                Semantics(
                  liveRegion: true,
                  label: w('digits', {'n': '${_digits.length}'}),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < 4; i++)
                      Container(
                        width: 56,
                        height: 64,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: i == _digits.length ? c.accent : c.lineStrong, width: i == _digits.length ? 2 : 1)),
                        child: Text(i < _digits.length ? _digits[i] : '', style: t.headlineSmall),
                      ),
                  ]),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final k in const ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'clr', '0', 'del'])
                      OutlinedButton(
                        onPressed: () => _key(k),
                        child: k == 'del'
                            ? Icon(Icons.backspace_outlined, semanticLabel: w('delete'))
                            : Text(k == 'clr' ? w('clear') : k, style: k == 'clr' ? t.labelLarge : t.headlineSmall),
                      ),
                  ],
                ),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.crit, fontWeight: FontWeight.w500))),
                const SizedBox(height: 16),
                FilledButton(onPressed: _find, child: Text(w('continue'))),
              ]);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, e) {
        // while the PIN box is showing, typing goes to it, not the check-in keypad
        if (e is! KeyDownEvent || (!widget.locked && !_unlocked)) return KeyEventResult.ignored;
        final ch = e.character;
        if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
          _key(ch);
        } else if (e.logicalKey == LogicalKeyboardKey.backspace) {
          _key('del');
        } else if (e.logicalKey == LogicalKeyboardKey.enter && _matches == null && _ticket == null) {
          _find();
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: ListView(padding: const EdgeInsets.all(24), children: [
        if (widget.locked)
          // the patient-facing tablet: only a discreet way out for staff, and back to full screen
          // if the browser left it (Esc)
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (!KioskLock.fullscreen) TextButton.icon(onPressed: KioskLock.enterFullscreen, icon: const Icon(Icons.fullscreen), label: Text(tr('Full screen'))),
            IconButton(tooltip: tr('Staff: leave check-in mode'), onPressed: _askToExit, icon: Icon(Icons.lock_outline, color: c.muted)),
          ])
        else
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end, spacing: 16, runSpacing: 12, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Semantics(header: true, child: Text(tr('Check-in tablet'), style: t.headlineMedium)),
            ]),
            if (_unlocked) FilledButton.icon(onPressed: widget.onLock, icon: const Icon(Icons.fullscreen), label: Text(tr('Full screen'))),
          ]),
        const SizedBox(height: 20),
        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
            child: widget.locked || _unlocked ? body : _gate(c, t),
          ),
        ),
      ]),
    );
  }

  /// Before the tablet runs: the PIN, or how to set one.
  Widget _gate(CfColors c, TextTheme t) => FutureBuilder<bool>(
        future: _pinSet,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
          if (!snap.data!) {
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 36, color: c.muted),
              const SizedBox(height: 12),
              Text(tr('Set a tablet PIN first'), style: t.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(tr('A clinic admin sets it in Settings.'),
                  style: t.bodyMedium?.copyWith(color: c.muted), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: () => setState(() => _pinSet = widget.desk.kioskPinSet()), child: Text(tr('I’ve set it, check again'))),
            ]);
          }
          return PinEntry(
            desk: widget.desk,
            title: tr('Start the check-in tablet'),
            note: tr('Then press Full screen to hand the tablet to patients.'),
            onOk: () {
              setState(() => _unlocked = true);
              _focus.requestFocus();
            },
          );
        },
      );
}
