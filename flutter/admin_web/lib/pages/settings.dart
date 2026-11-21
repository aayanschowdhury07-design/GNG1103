import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../ui.dart';

/// The clinic admin's settings: which optional features the clinic uses, its booking rules
/// and its reminders. Every change is saved at once and recorded in the audit log.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: setup,
      builder: (context, _) {
        final t = Theme.of(context).textTheme, c = CfColors.of(context);
        final features = Map<String, dynamic>.from(setup.clinic['features'] ?? const {});
        final rules = Map<String, dynamic>.from(setup.clinic['rules'] ?? const {});
        final admin = desk.me.isAdmin;

        Widget toggle(String title, String? note, bool value, Future<void> Function(bool) save) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title, style: t.bodyLarge),
              subtitle: note == null ? null : Text(note, style: t.bodySmall),
              value: value,
              onChanged: admin ? (v) => act(context, () => save(v), done: v ? tr('{title}: on', {'title': title}) : tr('{title}: off', {'title': title})) : null,
            );

        Widget choice(String key, String label, List<(int, String)> options, int fallback) {
          final current = options.any((o) => o.$1 == rules[key]) ? rules[key] as int : fallback;
          return SizedBox(
            width: 280,
            child: DropdownButtonFormField<int>(
              key: ValueKey('$key$current'),
              initialValue: current,
              decoration: InputDecoration(labelText: tr(label)),
              items: [for (final (v, l) in options) DropdownMenuItem(value: v, child: Text(tr(l)))],
              onChanged: admin
                  ? (v) => act(context, () async {
                        await setup.setRule(key, v!);
                        await desk.record('settings.update', 'CLINIC', '$label: ${options.firstWhere((o) => o.$1 == v).$2}');
                      }, done: tr('Saved'))
                  : null,
            ),
          );
        }

        Widget remind(String key, String label) => toggle(tr(label), null, rules[key] ?? true, (v) async {
              await setup.setRule(key, v);
              await desk.record('settings.update', 'CLINIC', '$label: ${v ? 'on' : 'off'}');
            });

        Widget divider() => Container(height: 1, color: c.line, margin: const EdgeInsets.symmetric(vertical: 4));

        final keys = clinicFeatures.keys.toList();
        return PageFrame(
          title: tr('Settings'),
          children: [
            Panel(
              title: tr('Features'),
              note: tr('Turning a feature off hides it from staff and patients. Nothing is deleted.'),
              child: Column(children: [
                for (final (i, k) in keys.indexed) ...[
                  if (i > 0) divider(),
                  toggle(tr(clinicFeatures[k]!.$1), tr(clinicFeatures[k]!.$2), features[k] != false, (v) => desk.setFeature(k, v)),
                ],
                divider(),
                toggle(tr('Listed in the patient directory'), tr('Patients can find you in the app. Off: only people with your booking link or QR code can book.'),
                    setup.clinic['listed'] != false, desk.setListed),
              ]),
            ),
            if (features['kiosk'] != false) _KioskPin(desk: desk),
            Columns(children: [
              Panel(
                title: tr('Booking rules'),
                child: Wrap(spacing: 16, runSpacing: 16, children: [
                  choice('cancelWindowHours', 'Free cancellation until', const [(12, '12 hours before'), (24, '24 hours before'), (48, '48 hours before')], 24),
                  choice('cutoffMinutes', 'Same-day online booking', const [(60, 'Up to 1 hour before'), (120, 'Up to 2 hours before'), (-1, 'Not allowed')], 60),
                  if (features['waitlist'] != false)
                    choice('offerHoldMinutes', 'A waitlist offer is held for', const [(15, '15 minutes'), (30, '30 minutes'), (60, '1 hour')], 30),
                ]),
              ),
              Panel(
                title: tr('Reminders'),
                note: tr('Texts cost money; push and email are free.'),
                child: Column(children: [
                  remind('remind48', '48 hours before (push, then email)'),
                  divider(),
                  remind('remind24', '24 hours before (push, then text)'),
                ]),
              ),
            ]),
          ],
        );
      },
    );
  }
}

/// The PIN staff enter to start the check-in tablet and to take it out of full screen.
class _KioskPin extends StatefulWidget {
  const _KioskPin({required this.desk});
  final ClinicDesk desk;
  @override
  State<_KioskPin> createState() => _KioskPinState();
}

class _KioskPinState extends State<_KioskPin> {
  late Future<bool> _set = widget.desk.kioskPinSet();

  Future<void> _change() async {
    final pin = await showDialog<String>(context: context, builder: (_) => const _NewPinDialog());
    if (pin == null || !mounted) return;
    await act(context, () => widget.desk.setKioskPin(pin), done: tr('Tablet PIN saved'));
    setState(() => _set = widget.desk.kioskPinSet());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    return Panel(
      title: tr('Check-in tablet PIN'),
      note: tr('Needed to start the check-in tablet and to leave full screen. Share it only with staff.'),
      child: FutureBuilder<bool>(
        future: _set,
        builder: (context, snap) => Row(children: [
          Icon(snap.data == true ? Icons.lock_outline : Icons.lock_open, color: snap.data == true ? c.good : c.warn, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(!snap.hasData ? tr('Checking…') : snap.data! ? tr('A 6-digit PIN is set.') : tr('No PIN yet: the check-in tablet can’t be started until one is set.'), style: t.bodyMedium)),
          if (widget.desk.me.isAdmin && snap.hasData) OutlinedButton(onPressed: _change, child: Text(snap.data! ? tr('Change PIN') : tr('Set PIN'))),
        ]),
      ),
    );
  }
}

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog();
  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _a = TextEditingController(), _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _save() {
    if (_a.text.length != 6) return setState(() => _error = tr('The PIN must be 6 digits.'));
    if (RegExp(r'^(\d)\1{5}$').hasMatch(_a.text) || '0123456789'.contains(_a.text) || '9876543210'.contains(_a.text)) {
      return setState(() => _error = tr('Pick a PIN that’s harder to guess (not 111111 or 123456).'));
    }
    if (_a.text != _b.text) return setState(() => _error = tr('The two PINs don’t match.'));
    Navigator.pop(context, _a.text);
  }

  @override
  Widget build(BuildContext context) {
    TextField field(TextEditingController ctl, String label, {bool focus = false}) => TextField(
          controller: ctl,
          autofocus: focus,
          obscureText: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, counterText: ''),
          onSubmitted: (_) => _save(),
        );
    return AlertDialog(
      title: Text(tr('Set the tablet PIN')),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          field(_a, tr('New 6-digit PIN'), focus: true),
          const SizedBox(height: 12),
          field(_b, tr('Type it again')),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: CfColors.of(context).crit))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(onPressed: _save, child: Text(tr('Save PIN'))),
      ],
    );
  }
}
