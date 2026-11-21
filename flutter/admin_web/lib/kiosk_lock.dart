import 'dart:async';
import 'dart:js_interop';

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'l10n.dart';

/// The browser's full screen, and the "this browser is a locked check-in tablet" flag that
/// survives a reload, so reloading the page doesn't open the staff website.
class KioskLock {
  static const _key = 'cf.kioskLock';

  static bool get fullscreen => web.document.fullscreenElement != null;

  static Future<void> enterFullscreen() async {
    try {
      await web.document.documentElement?.requestFullscreen().toDart;
    } catch (_) {
      // the browser refused (no tap, or not allowed); the tablet still works, just not full screen
    }
  }

  static Future<void> exitFullscreen() async {
    if (!fullscreen) return;
    try {
      await web.document.exitFullscreen().toDart;
    } catch (_) {}
  }

  /// Calls [onChange] whenever the browser enters or leaves full screen (Esc included).
  static void Function() onFullscreenChange(void Function() onChange) {
    final listener = ((web.Event _) => onChange()).toJS;
    web.document.addEventListener('fullscreenchange', listener);
    return () => web.document.removeEventListener('fullscreenchange', listener);
  }

  /// The clinic this browser is locked to as a check-in tablet, if any.
  static String? get lockedClinic {
    try {
      return web.window.localStorage.getItem(_key);
    } catch (_) {
      return null;
    }
  }

  static set lockedClinic(String? clinicId) {
    try {
      clinicId == null ? web.window.localStorage.removeItem(_key) : web.window.localStorage.setItem(_key, clinicId);
    } catch (_) {}
  }
}

/// A 6-digit PIN entry: checks it with the clinic and calls [onOk]. After 5 wrong tries it
/// waits 30 seconds before taking another.
class PinEntry extends StatefulWidget {
  const PinEntry({super.key, required this.desk, required this.title, required this.note, required this.onOk, this.onCancel});
  final ClinicDesk desk;
  final String title, note;
  final VoidCallback onOk;
  final VoidCallback? onCancel;
  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;
  int _wrong = 0;
  DateTime? _waitUntil;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final wait = _waitUntil?.difference(DateTime.now());
    if (wait != null && !wait.isNegative) return setState(() => _error = tr('Too many tries. Wait {n} seconds.', {'n': wait.inSeconds + 1}));
    if (_pin.text.length != 6) return setState(() => _error = tr('Enter all 6 digits.'));
    setState(() => _busy = true);
    bool ok;
    try {
      ok = await widget.desk.checkKioskPin(_pin.text);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) return widget.onOk();
    _wrong++;
    _pin.clear();
    setState(() {
      _busy = false;
      if (_wrong >= 5) {
        _wrong = 0;
        _waitUntil = DateTime.now().add(const Duration(seconds: 30));
        _error = tr('Too many tries. Wait {n} seconds.', {'n': 30});
      } else {
        _error = tr('That PIN isn’t right.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Icon(Icons.lock_outline, size: 36, color: c.accent),
      const SizedBox(height: 12),
      Text(widget.title, style: t.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(widget.note, style: t.bodyMedium?.copyWith(color: c.muted), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      TextField(
        controller: _pin,
        autofocus: true,
        obscureText: true,
        maxLength: 6,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: t.headlineSmall?.copyWith(letterSpacing: 12),
        decoration: InputDecoration(labelText: tr('Tablet PIN'), counterText: ''),
        onSubmitted: (_) => _submit(),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.crit), textAlign: TextAlign.center)),
      const SizedBox(height: 16),
      FilledButton(onPressed: _busy ? null : _submit, child: Text(tr('Unlock'))),
      if (widget.onCancel != null) TextButton(onPressed: widget.onCancel, child: Text(tr('Cancel'))),
    ]);
  }
}
