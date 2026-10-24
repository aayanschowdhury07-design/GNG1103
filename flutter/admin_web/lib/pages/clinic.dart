import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../steps.dart';
import '../ui.dart';
import '../visit.dart';

/// Services, clinicians and their hours, time off and breaks, and the kinds of unavailable time.
class ClinicPage extends StatelessWidget {
  const ClinicPage({super.key, required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'Services & clinicians',
        children: [
          Columns(children: [
            Panel(child: ServicesEditor(setup: setup)),
            Panel(child: CliniciansEditor(setup: setup)),
          ]),
          _TimeOff(setup: setup, desk: desk),
          _BlockTypes(setup: setup, desk: desk),
        ],
      );
}

List<Map<String, String>> _types(ClinicSetup s) =>
    [for (final x in (s.clinic['blockTypes'] as List?) ?? defaultBlockTypes) Map<String, String>.from((x as Map).map((k, v) => MapEntry('$k', '$v')))];

class _TimeOff extends StatefulWidget {
  const _TimeOff({required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;
  @override
  State<_TimeOff> createState() => _TimeOffState();
}

class _TimeOffState extends State<_TimeOff> {
  String? _clinician, _type, _error;
  late DateTime _date = DateTime.parse(widget.desk.today);
  bool _allDay = true;
  int _from = slotMinutes.first, _to = slotMinutes.last;

  Future<void> _add() async {
    final s = widget.setup;
    final cl = _clinician ?? s.clinicians.firstOrNull?.id, type = _type ?? _types(s).first['name'];
    if (cl == null) return setState(() => _error = 'Add a clinician first.');
    if (!_allDay && _to < _from) return setState(() => _error = 'The end must be after the start.');
    final minutes = _allDay ? null : slotMinutes.where((m) => m >= _from && m <= _to).toSet();
    final iso = isoDate(_date);
    // time off can't silently override a booking: those visits need moving first
    final clash = widget.desk.on(iso).where((a) => a.clinicianId == cl && a.active && (minutes == null || minutes.contains(a.minute))).toList();
    setState(() => _error = null);
    await act(
      context,
      () => widget.desk.addBlock(clinicianId: cl, type: type!, date: iso, minutes: minutes),
      done: clash.isEmpty
          ? '$type added for ${clinicianShort(s, cl)}'
          : '$type added. ${clash.length} booked visit${clash.length == 1 ? ' is' : 's are'} still in that time; move or cancel ${clash.length == 1 ? 'it' : 'them'}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.setup, d = widget.desk, t = Theme.of(context).textTheme;
    final types = _types(s);
    // what's still ahead (or applies every day), soonest first
    final blocks = [...d.blocks.where((b) => b.date == null || b.date!.compareTo(d.today) >= 0)]..sort((a, b) => (a.date ?? '').compareTo(b.date ?? ''));
    return Panel(
      title: 'Time off and breaks',
      note: 'Shown as unavailable on the calendar. Never bookable online.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SimpleTable(
          columns: const ['Clinician', 'Type', 'When', ''],
          empty: 'No time off or breaks yet.',
          rows: [
            for (final b in blocks)
              [
                Text(clinicianShort(s, b.clinicianId)),
                Text(b.type),
                Text('${b.date == null ? 'Every day' : shortDate(b.date!)} · ${b.minutes == null ? 'all day' : '${formatTime(b.minutes!.reduce((a, b) => a < b ? a : b))} to ${formatTime(b.minutes!.reduce((a, b) => a > b ? a : b) + 30)}'}', style: t.bodySmall),
                RowActions([small('Remove', () => act(context, () => d.removeBlock(b), done: '${b.type} removed'), danger: true)]),
              ],
          ],
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              initialValue: _clinician ?? s.clinicians.firstOrNull?.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Clinician'),
              items: [for (final c in s.clinicians) DropdownMenuItem(value: c.id, child: Text(c.short.isEmpty ? c.name : c.short))],
              onChanged: (v) => setState(() => _clinician = v),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              initialValue: _type ?? types.first['name'],
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [for (final x in types) DropdownMenuItem(value: x['name'], child: Text(x['name']!))],
              onChanged: (v) => setState(() => _type = v),
            ),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.event, size: 18),
            label: Text(shortDate(isoDate(_date))),
            onPressed: () async {
              final today = DateTime.parse(widget.desk.today);
              final picked = await showDatePicker(context: context, initialDate: _date, firstDate: today, lastDate: today.add(const Duration(days: 365)));
              if (picked != null) setState(() => _date = picked);
            },
          ),
          FilterChip(label: const Text('All day'), selected: _allDay, onSelected: (v) => setState(() => _allDay = v)),
          if (!_allDay) ...[
            _time('From', _from, (v) => setState(() => _from = v)),
            _time('Until the end of', _to, (v) => setState(() => _to = v)),
          ],
          FilledButton(onPressed: _add, child: const Text('Add')),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: t.bodyMedium?.copyWith(color: CfColors.of(context).crit))),
      ]),
    );
  }

  Widget _time(String label, int value, ValueChanged<int> onChanged) => SizedBox(
        width: 170,
        child: DropdownButtonFormField<int>(
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          items: [for (final m in slotMinutes) DropdownMenuItem(value: m, child: Text(formatTime(m)))],
          onChanged: (v) => onChanged(v!),
        ),
      );
}

class _BlockTypes extends StatefulWidget {
  const _BlockTypes({required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;
  @override
  State<_BlockTypes> createState() => _BlockTypesState();
}

class _BlockTypesState extends State<_BlockTypes> {
  final _name = TextEditingController();
  String _scope = 'Each clinician';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final types = _types(widget.setup);
    return Panel(
      title: 'Unavailable time types',
      note: 'The kinds of unavailable time staff can choose from.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SimpleTable(
          columns: const ['Type', 'Applies to', 'On the calendar', ''],
          rows: [
            for (final (i, x) in types.indexed)
              [
                Text(x['name']!),
                Text(x['scope'] ?? '', style: t.bodySmall),
                Container(
                  width: 140,
                  height: 24,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(6)),
                  child: Text(x['name']!, style: t.labelMedium?.copyWith(color: c.muted)),
                ),
                RowActions([
                  small('Remove', () {
                    final next = [...types]..removeAt(i);
                    act(context, () => widget.desk.setBlockTypes(next, 'Unavailable time type removed: ${x['name']}'),
                        done: '${x['name']} removed', undo: () => widget.desk.setBlockTypes(types, 'Unavailable time type restored: ${x['name']}'));
                  }, danger: true),
                ]),
              ],
          ],
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 240, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'New type', hintText: 'e.g. Team meeting'))),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              initialValue: _scope,
              decoration: const InputDecoration(labelText: 'Applies to'),
              items: const [DropdownMenuItem(value: 'Each clinician', child: Text('Each clinician')), DropdownMenuItem(value: 'Whole clinic', child: Text('Whole clinic'))],
              onChanged: (v) => setState(() => _scope = v!),
            ),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add type'),
            onPressed: () {
              final name = _name.text.trim();
              if (name.isEmpty) return say(context, 'Name the type first');
              _name.clear();
              act(context, () => widget.desk.setBlockTypes([...types, {'name': name, 'scope': _scope}], 'Unavailable time type added: $name'), done: '$name added');
            },
          ),
        ]),
      ]),
    );
  }
}
