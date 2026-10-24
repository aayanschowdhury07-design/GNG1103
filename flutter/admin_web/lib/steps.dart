import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Shows the current setup step. Each step saves its own data and then calls completeStep.
class SetupStep extends StatelessWidget {
  const SetupStep({super.key, required this.setup, required this.step});
  final ClinicSetup setup;
  final int step;

  @override
  Widget build(BuildContext context) => switch (step) {
        1 => ProfileStep(key: const ValueKey(1), setup: setup),
        2 => ServicesStep(key: const ValueKey(2), setup: setup),
        3 => CliniciansStep(key: const ValueKey(3), setup: setup),
        4 => ExistingStep(key: const ValueKey(4), setup: setup),
        5 => BookingLinkStep(key: const ValueKey(5), setup: setup),
        6 => RulesStep(key: const ValueKey(6), setup: setup),
        7 => StaffStep(key: const ValueKey(7), setup: setup),
        _ => DirectoryStep(key: const ValueKey(8), setup: setup),
      };
}

// ---------------------------------------------------------------- shared pieces

/// A step: heading, one-line purpose, the form, and Back / Save and continue at the bottom.
class StepFrame extends StatefulWidget {
  const StepFrame({super.key, required this.setup, required this.step, required this.intro, required this.children, this.onSave, this.nextLabel});
  final ClinicSetup setup;
  final int step;
  final String intro;
  final List<Widget> children;

  /// Saves the step; return an error message to stay on the step, or null to continue.
  final Future<String?> Function()? onSave;
  final String? nextLabel;

  @override
  State<StepFrame> createState() => _StepFrameState();
}

class _StepFrameState extends State<StepFrame> {
  bool _busy = false;
  String? _error;

  Future<void> _next() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final err = await widget.onSave?.call();
      if (err != null) {
        setState(() => _error = err);
      } else {
        await widget.setup.completeStep(widget.step);
      }
    } catch (e) {
      setState(() => _error = 'Couldn’t save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    final last = widget.step == setupSteps.length;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(32, 28, 32, 32), children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Step ${widget.step} of ${setupSteps.length}', style: t.bodySmall),
                Semantics(header: true, child: Text(setupSteps[widget.step - 1], style: t.headlineMedium)),
                const SizedBox(height: 6),
                Text(widget.intro, style: t.bodyMedium?.copyWith(color: c.muted)),
                const SizedBox(height: 24),
                ...widget.children,
              ]),
            ),
          ),
        ]),
      ),
      Container(
        decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line))),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Row(children: [
              if (widget.step > 1) TextButton(onPressed: () => widget.setup.goToStep(widget.step - 1), child: const Text('Back')),
              const SizedBox(width: 12),
              if (_error != null) Expanded(child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.crit, fontWeight: FontWeight.w500))) else const Spacer(),
              const SizedBox(width: 12),
              FilledButton(onPressed: _busy ? null : _next, child: Text(widget.nextLabel ?? (last ? 'Finish setup' : 'Save and continue'))),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// A titled group inside a step, separated by a hairline.
class Group extends StatelessWidget {
  const Group({super.key, required this.title, this.note, required this.child});
  final String title;
  final String? note;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: t.titleMedium),
        if (note != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(note!, style: t.bodySmall)),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

String hhmm(int m) => formatTime(m);
final _halfHours = [for (var m = 7 * 60; m <= 21 * 60; m += 30) m];

// ---------------------------------------------------------------- 1. profile

const _brands = {'blue': Color(0xFF2C4C7C), 'teal': Color(0xFF1F5E63), 'green': Color(0xFF285E44), 'plum': Color(0xFF5E3A63)};
const _kinds = ['Physiotherapy', 'Chiropractic', 'Massage therapy', 'Family practice', 'Walk-in', 'Mental health', 'Rehab', 'Dental'];

class ProfileStep extends StatefulWidget {
  const ProfileStep({super.key, required this.setup});
  final ClinicSetup setup;
  @override
  State<ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends State<ProfileStep> {
  late final Map<String, dynamic> _c = widget.setup.clinic;
  late final _name = TextEditingController(text: _c['name']);
  late final _address = TextEditingController(text: _c['address']);
  late final _city = TextEditingController(text: _c['city']);
  late final _phone = TextEditingController(text: _c['phone']);
  late final Set<String> _kind = {for (final k in (_c['kind'] as String? ?? '').split(',')) if (k.trim().isNotEmpty) k.trim()};
  late String _brand = _c['brand'] ?? 'blue';
  late final Set<String> _languages = {...List<String>.from(_c['languages'] ?? const ['en'])};
  late LatLng _pin = LatLng((_c['lat'] as num).toDouble(), (_c['lng'] as num).toDouble());
  bool _pinMoved = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _city, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _save() async {
    if (_name.text.trim().isEmpty) return 'Enter the clinic’s name.';
    if (_address.text.trim().isEmpty) return 'Enter the street address patients come to.';
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 10) return 'Enter the clinic’s phone number with area code.';
    if (_kind.isEmpty) return 'Choose at least one kind of care, so patients can find you.';
    if (!_pinMoved && widget.setup.doneSteps.isEmpty) return 'Click the map where the clinic is, so it shows in the right place.';
    await widget.setup.saveProfile(
      name: _name.text,
      address: _address.text,
      city: _city.text,
      phone: _phone.text,
      kind: _kind.join(', '),
      brand: _brand,
      languages: _languages.toList(),
      lat: _pin.latitude,
      lng: _pin.longitude,
    );
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    return StepFrame(
      setup: widget.setup,
      step: 1,
      intro: 'Patients see this name, address and colour on the booking page, in messages and in the clinic directory.',
      onSave: _save,
      children: [
        Group(
          title: 'Clinic',
          child: Wrap(spacing: 16, runSpacing: 12, children: [
            _field(_name, 'Clinic name', 360),
            _field(_phone, 'Phone', 220, keyboard: TextInputType.phone),
            _field(_address, 'Street address', 360),
            _field(_city, 'City and province', 220, hint: 'e.g. Toronto, ON'),
          ]),
        ),
        Group(
          title: 'Kind of care',
          note: 'Patients search the directory by these.',
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in _kinds) FilterChip(label: Text(k), selected: _kind.contains(k), onSelected: (on) => setState(() => on ? _kind.add(k) : _kind.remove(k))),
          ]),
        ),
        Group(
          title: 'Where patients find you',
          note: _pinMoved ? 'Pinned. Drag the map or click again to adjust.' : 'Click the map where the clinic’s entrance is.',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 280,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: _pin,
                  initialZoom: 14,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  onTap: (_, p) => setState(() {
                    _pin = p;
                    _pinMoved = true;
                  }),
                ),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'ca.clinicflow.admin'),
                  MarkerLayer(markers: [
                    Marker(point: _pin, width: 40, height: 40, alignment: Alignment.topCenter, child: Icon(Icons.location_on, size: 40, color: c.accent)),
                  ]),
                  const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
                ],
              ),
            ),
          ),
        ),
        Group(
          title: 'Brand colour',
          child: Row(children: [
            for (final e in _brands.entries)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Semantics(
                  button: true,
                  selected: _brand == e.key,
                  label: '${e.key} brand colour',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _brand = e.key),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: e.value,
                        shape: BoxShape.circle,
                        border: Border.all(color: _brand == e.key ? c.fg : c.surface, width: 3),
                        boxShadow: [BoxShadow(color: c.lineStrong, spreadRadius: 1)],
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        Group(
          title: 'Languages',
          note: 'Patient messages and the booking page are offered in these.',
          child: Wrap(spacing: 8, children: [
            for (final (k, l) in const [('en', 'English'), ('fr', 'Français')])
              FilterChip(
                label: Text(l),
                selected: _languages.contains(k),
                onSelected: (on) => setState(() {
                  if (on) {
                    _languages.add(k);
                  } else if (_languages.length > 1) {
                    _languages.remove(k); // at least one language stays on
                  }
                }),
              ),
          ]),
        ),
        Text('One location for now. Clinics with several locations come later.', style: t.bodySmall),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, double width, {String? hint, TextInputType? keyboard}) =>
      SizedBox(width: width, child: TextField(controller: c, keyboardType: keyboard, decoration: InputDecoration(labelText: label, hintText: hint)));
}

// ---------------------------------------------------------------- 2. services

class ServicesStep extends StatelessWidget {
  const ServicesStep({super.key, required this.setup});
  final ClinicSetup setup;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: setup,
        builder: (context, _) => StepFrame(
          setup: setup,
          step: 2,
          intro: 'What patients can book, and how long each visit takes. You choose who offers each one in the next step.',
          onSave: () async => setup.services.isEmpty ? 'Add at least one service.' : null,
          children: [ServicesEditor(setup: setup)],
        ),
      );
}

/// The clinic's services, with a form to add one. Used by the wizard and the Services page.
class ServicesEditor extends StatefulWidget {
  const ServicesEditor({super.key, required this.setup});
  final ClinicSetup setup;
  @override
  State<ServicesEditor> createState() => _ServicesEditorState();
}

class _ServicesEditorState extends State<ServicesEditor> {
  final _name = TextEditingController(), _nameFr = TextEditingController(), _who = TextEditingController();
  int _minutes = 30;
  bool _online = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _nameFr.dispose();
    _who.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Name the service first.');
    await widget.setup.addService(name: _name.text, nameFr: _nameFr.text, minutes: _minutes, online: _online, who: _who.text);
    _name.clear();
    _nameFr.clear();
    _who.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    return ListenableBuilder(
      listenable: widget.setup,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Group(
            title: 'Services',
            child: Column(children: [
              if (widget.setup.services.isEmpty) Align(alignment: Alignment.centerLeft, child: Text('None yet. Add your first one below.', style: t.bodySmall)),
              for (final s in widget.setup.services)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.name),
                  subtitle: Text('${s.minutes} min${s.nameFr.isEmpty ? '' : ' · FR: ${s.nameFr}'}${s.who.isEmpty ? '' : ' · ${s.who}'}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(s.online ? 'Bookable online' : 'Front desk only', style: t.bodySmall),
                    Switch(value: s.online, onChanged: (v) => widget.setup.setServiceOnline(s.id, v)),
                    IconButton(tooltip: 'Remove ${s.name}', icon: Icon(Icons.delete_outline, color: c.crit), onPressed: () => widget.setup.removeService(s.id)),
                  ]),
                ),
            ]),
          ),
          Group(
            title: 'Add a service',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
                SizedBox(width: 300, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Physiotherapy · follow-up'))),
                SizedBox(width: 300, child: TextField(controller: _nameFr, decoration: const InputDecoration(labelText: 'French name (optional)', hintText: 'e.g. Physiothérapie · suivi'))),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<int>(
                    initialValue: _minutes,
                    decoration: const InputDecoration(labelText: 'Length'),
                    items: [for (final m in const [10, 15, 20, 30, 45, 50, 60, 90]) DropdownMenuItem(value: m, child: Text('$m min'))],
                    onChanged: (v) => setState(() => _minutes = v!),
                  ),
                ),
                SizedBox(width: 300, child: TextField(controller: _who, decoration: const InputDecoration(labelText: 'Who it’s for (optional)', hintText: 'e.g. Returning patients'))),
                SizedBox(width: 220, child: SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Bookable online'), value: _online, onChanged: (v) => setState(() => _online = v))),
              ]),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.crit))),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add service')),
            ]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 3. clinicians

class CliniciansStep extends StatelessWidget {
  const CliniciansStep({super.key, required this.setup});
  final ClinicSetup setup;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: setup,
        builder: (context, _) => StepFrame(
          setup: setup,
          step: 3,
          intro: 'Who sees patients, the days and hours they work, and which services they offer. Breaks and time off can be added later.',
          onSave: () async => setup.clinicians.isEmpty ? 'Add at least one clinician.' : null,
          children: [CliniciansEditor(setup: setup)],
        ),
      );
}

/// The clinicians, their hours and services, with a form to add one. Used by the wizard and
/// the Services & clinicians page.
class CliniciansEditor extends StatefulWidget {
  const CliniciansEditor({super.key, required this.setup});
  final ClinicSetup setup;
  @override
  State<CliniciansEditor> createState() => _CliniciansEditorState();
}

class _CliniciansEditorState extends State<CliniciansEditor> {
  final _name = TextEditingController(), _role = TextEditingController();
  final Set<String> _days = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri'};
  int _start = 9 * 60, _end = 17 * 60;
  Set<String>? _services; // null until the services have loaded: then all are ticked
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final err = _name.text.trim().isEmpty
        ? 'Enter the clinician’s name.'
        : _role.text.trim().isEmpty
            ? 'Enter their role, e.g. Physiotherapist.'
            : _days.isEmpty
                ? 'Pick the days they work.'
                : _end <= _start
                    ? 'The end of their day must be after the start.'
                    : null;
    if (err != null) return setState(() => _error = err);
    await widget.setup.addClinician(name: _name.text, role: _role.text, days: weekdays.where(_days.contains).toList(), start: _start, end: _end, serviceIds: (_services ?? {}).toList());
    _name.clear();
    _role.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    return ListenableBuilder(
      listenable: widget.setup,
      builder: (context, _) {
        final s = widget.setup;
        _services ??= s.services.isEmpty ? null : {for (final x in s.services) x.id};
        final unstaffed = s.services.where((x) => x.clinicianIds.isEmpty).map((x) => x.name).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Group(
              title: 'Clinicians',
              child: Column(children: [
                if (s.clinicians.isEmpty) Align(alignment: Alignment.centerLeft, child: Text('None yet. Add your first one below.', style: t.bodySmall)),
                for (final cl in s.clinicians)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${cl.name} · ${cl.role}'),
                    subtitle: Text('${cl.days.join(', ')} · ${hhmm(cl.start)} to ${hhmm(cl.end)}\n'
                        'Offers: ${s.services.where((x) => x.clinicianIds.contains(cl.id)).map((x) => x.name).join(', ').ifEmpty('no services yet')}'),
                    isThreeLine: true,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: 'Edit hours for ${cl.name}', icon: const Icon(Icons.schedule), onPressed: () => _editHours(cl)),
                      IconButton(tooltip: 'Remove ${cl.name}', icon: Icon(Icons.delete_outline, color: c.crit), onPressed: () => s.removeClinician(cl.id)),
                    ]),
                  ),
                if (unstaffed.isNotEmpty && s.clinicians.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text('Nobody offers ${unstaffed.join(', ')} yet, so patients can’t book it.', style: t.bodyMedium?.copyWith(color: c.warn)),
                  ),
              ]),
            ),
            Group(
              title: 'Add a clinician',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 16, runSpacing: 12, children: [
                  SizedBox(width: 300, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Dr. Kwame Osei'))),
                  SizedBox(width: 300, child: TextField(controller: _role, decoration: const InputDecoration(labelText: 'Role', hintText: 'e.g. Physiotherapist'))),
                ]),
                const SizedBox(height: 16),
                Text('Days', style: t.labelLarge),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  for (final d in weekdays) FilterChip(label: Text(d), selected: _days.contains(d), onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d))),
                ]),
                const SizedBox(height: 16),
                Wrap(spacing: 16, runSpacing: 12, children: [
                  _time('Starts', _start, (v) => setState(() => _start = v)),
                  _time('Ends', _end, (v) => setState(() => _end = v)),
                ]),
                const SizedBox(height: 16),
                Text('Offers', style: t.labelLarge),
                if (s.services.isEmpty) Text('Add services in step 2 first.', style: t.bodySmall),
                for (final x in s.services)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: Text('${x.name} · ${x.minutes} min'),
                    value: _services?.contains(x.id) ?? false,
                    onChanged: (on) => setState(() => on! ? _services!.add(x.id) : _services!.remove(x.id)),
                  ),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.crit))),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add clinician')),
              ]),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editHours(SetupClinician cl) async {
    final days = {...cl.days};
    var start = cl.start, end = cl.end;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text('Hours for ${cl.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in weekdays) FilterChip(label: Text(d), selected: days.contains(d), onSelected: (on) => set(() => on ? days.add(d) : days.remove(d))),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 16, runSpacing: 12, children: [
              _time('Starts', start, (v) => set(() => start = v)),
              _time('Ends', end, (v) => set(() => end = v)),
            ]),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: CfColors.of(context).crit))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (days.isEmpty || end <= start) return set(() => error = days.isEmpty ? 'Pick the days they work.' : 'The end of their day must be after the start.');
                await widget.setup.updateClinicianHours(cl.id, days: weekdays.where(days.contains).toList(), start: start, end: end);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _time(String label, int value, ValueChanged<int> onChanged) => SizedBox(
        width: 160,
        child: DropdownButtonFormField<int>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: [for (final m in _halfHours) DropdownMenuItem(value: m, child: Text(hhmm(m)))],
          onChanged: (v) => onChanged(v!),
        ),
      );
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

// ---------------------------------------------------------------- 4. existing appointments

class ExistingStep extends StatelessWidget {
  const ExistingStep({super.key, required this.setup});
  final ClinicSetup setup;

  @override
  Widget build(BuildContext context) {
    const options = [
      ('fresh', 'Start fresh', 'Patients book through your link from now on. Recommended.'),
      ('hand', 'Add upcoming appointments by hand', 'From the calendar once setup is done.'),
      ('ics', 'Import a calendar file later', 'An .ics export from your current system.'),
    ];
    return ListenableBuilder(
      listenable: setup,
      builder: (context, _) => StepFrame(
        setup: setup,
        step: 4,
        intro: 'Optional. No spreadsheet is needed to finish setup.',
        children: [
          for (final (k, title, sub) in options)
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: setup.clinic['existing'] == k,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(setup.clinic['existing'] == k ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: CfColors.of(context).accent),
                title: Text(title),
                subtitle: Text(sub),
                onTap: () => setup.setExisting(k),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 5. booking link

class BookingLinkStep extends StatelessWidget {
  const BookingLinkStep({super.key, required this.setup});
  final ClinicSetup setup;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    final url = 'https://book.clinicflow.ca/${setup.clinicId}';
    return StepFrame(
      setup: setup,
      step: 5,
      intro: 'Patients scan this or tap the link, pick a time and confirm with a text code. No app or account needed.',
      children: [
        Wrap(spacing: 32, runSpacing: 24, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
            child: QrImageView(data: url, size: 180, semanticsLabel: 'QR code for $url'),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your booking link', style: t.titleMedium),
              const SizedBox(height: 6),
              SelectableText(url, style: t.bodyLarge?.copyWith(color: c.accent)),
              const SizedBox(height: 12),
              Text('Print the QR code for the front desk, the door and appointment cards.', style: t.bodySmall),
              const SizedBox(height: 8),
              Text('The link starts working when the patient web app is published (Firebase Hosting).', style: t.bodySmall?.copyWith(color: c.warn)),
            ]),
          ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------- 6. rules

class RulesStep extends StatelessWidget {
  const RulesStep({super.key, required this.setup});
  final ClinicSetup setup;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: setup,
      builder: (context, _) {
        final r = Map<String, dynamic>.from(setup.clinic['rules'] ?? const {});
        Widget choice(String key, String label, List<(int, String)> options) => SizedBox(
              width: 260,
              child: DropdownButtonFormField<int>(
                key: ValueKey('$key${r[key]}'),
                initialValue: r[key],
                decoration: InputDecoration(labelText: label),
                items: [for (final (v, l) in options) DropdownMenuItem(value: v, child: Text(l))],
                onChanged: (v) => setup.setRule(key, v!),
              ),
            );
        return StepFrame(
          setup: setup,
          step: 6,
          intro: 'How cancellations, waitlist offers and reminders work at your clinic. Every change is recorded in the audit log.',
          children: [
            Group(
              title: 'Cancellations and booking',
              child: Wrap(spacing: 16, runSpacing: 16, children: [
                choice('cancelWindowHours', 'Free cancellation until', const [(12, '12 hours before'), (24, '24 hours before'), (48, '48 hours before')]),
                choice('cutoffMinutes', 'Same-day online booking', const [(60, 'Up to 1 hour before'), (120, 'Up to 2 hours before'), (-1, 'Not allowed')]),
              ]),
            ),
            Group(
              title: 'Waitlist',
              note: 'When a time frees up, it is offered to the first matching person on the waitlist.',
              child: choice('offerHoldMinutes', 'An offer is held for', const [(15, '15 minutes'), (30, '30 minutes'), (60, '1 hour')]),
            ),
            Group(
              title: 'Reminders',
              note: 'Each reminder has a one-tap confirm.',
              child: Column(children: [
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('48 hours before (push, then email)'), value: r['remind48'] ?? true, onChanged: (v) => setup.setRule('remind48', v)),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('24 hours before (push, then text)'), value: r['remind24'] ?? true, onChanged: (v) => setup.setRule('remind24', v)),
              ]),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- 7. staff

class StaffStep extends StatefulWidget {
  const StaffStep({super.key, required this.setup});
  final ClinicSetup setup;
  @override
  State<StaffStep> createState() => _StaffStepState();
}

class _StaffStepState extends State<StaffStep> {
  final _name = TextEditingController(), _email = TextEditingController();
  String _role = 'frontdesk';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Enter their name.');
    if (!_email.text.contains('@')) return setState(() => _error = 'Enter their work email.');
    await widget.setup.invite(name: _name.text, email: _email.text, role: _role);
    _name.clear();
    _email.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    return ListenableBuilder(
      listenable: widget.setup,
      builder: (context, _) {
        final s = widget.setup;
        return StepFrame(
          setup: s,
          step: 7,
          intro: 'Optional. Each person signs in with their own account, and their role decides what they can see and change.',
          children: [
            Group(
              title: 'Your team',
              child: Column(children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${s.user?.displayName ?? ''} (you)'),
                  subtitle: Text(s.user?.email ?? ''),
                  trailing: const Text('Admin'),
                ),
                for (final i in s.invites)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(i.name),
                    subtitle: Text('${i.email} · invited, hasn’t signed in yet'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(staffRoles[i.role] ?? i.role),
                      IconButton(tooltip: 'Cancel invitation for ${i.name}', icon: Icon(Icons.close, color: c.crit), onPressed: () => s.removeInvite(i.id)),
                    ]),
                  ),
              ]),
            ),
            Group(
              title: 'Invite someone',
              note: 'Admins can change everything; front desk runs the day; clinicians see their own patients; support has read-only access.',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 16, runSpacing: 12, children: [
                  SizedBox(width: 240, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name'))),
                  SizedBox(width: 280, child: TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Work email'))),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: _role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: [for (final e in staffRoles.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setState(() => _role = v!),
                    ),
                  ),
                ]),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.crit))),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: _invite, icon: const Icon(Icons.person_add_alt), label: const Text('Add invitation')),
                const SizedBox(height: 8),
                Text('Invitations are saved now; the email that sends them comes with the Cloud Functions step.', style: t.bodySmall?.copyWith(color: c.warn)),
              ]),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- 8. directory

class DirectoryStep extends StatelessWidget {
  const DirectoryStep({super.key, required this.setup});
  final ClinicSetup setup;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    return ListenableBuilder(
      listenable: setup,
      builder: (context, _) {
        final k = setup.clinic, listed = k['listed'] == true;
        return StepFrame(
          setup: setup,
          step: 8,
          intro: 'Optional. Listed clinics appear in the ClinicFlow app’s clinic map and search, so nearby patients can find your openings.',
          nextLabel: setup.finished ? 'Save' : 'Submit for review',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('List ${k['name']} in the ClinicFlow directory'),
              subtitle: const Text('Only your profile and open times are shared. Never patient names or reasons for visits.'),
              value: listed,
              onChanged: setup.setListed,
            ),
            const SizedBox(height: 16),
            Text('How patients will see you', style: t.titleMedium),
            const SizedBox(height: 8),
            Opacity(
              opacity: listed ? 1 : .45,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                child: Row(children: [
                  CircleAvatar(backgroundColor: c.accent, child: Text(k['initials'] ?? '', style: TextStyle(color: c.accentFg, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k['name'] ?? '', style: t.titleMedium),
                      Text('${k['address']}${(k['city'] as String? ?? '').isEmpty ? '' : ', ${k['city']}'} · ${k['kind']}', style: t.bodySmall),
                      Text('${setup.services.where((s) => s.online).length} services bookable online', style: t.bodySmall?.copyWith(color: c.good)),
                    ]),
                  ),
                ]),
              ),
            ),
            if (!setup.finished) ...[
              const SizedBox(height: 16),
              Text(
                'Submitting sends your clinic to ClinicFlow for a quick check of its name, address and phone, usually within one business day. '
                'Once it’s approved, patients can book you${listed ? ' and find you in the directory' : ' through your link'}. Your team can use the calendar meanwhile.',
                style: t.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }
}
