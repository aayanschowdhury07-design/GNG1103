import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../ui.dart';

/// What patients are told and when; the wording of each message; announcements; and every
/// message that has been sent or is waiting to go.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String _pick = messageTemplates.keys.first;
  final _en = TextEditingController(), _fr = TextEditingController(), _announce = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _en.text = widget.desk.template(_pick, 'en');
    _fr.text = widget.desk.template(_pick, 'fr');
  }

  @override
  void dispose() {
    _en.dispose();
    _fr.dispose();
    _announce.dispose();
    super.dispose();
  }

  static String _count(String text) {
    final segments = (text.length / 160).ceil().clamp(1, 99);
    return '${text.length} characters before {placeholders} are filled · $segments text segment${segments > 1 ? 's (costs more per message)' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context), d = widget.desk;
    final notice = widget.setup.clinic['notice'] as String?;
    Widget fr(String k) => d.template(k, 'fr').isEmpty ? const Pill('FR missing', tone: Tone.warn) : const Pill('EN · FR', tone: Tone.good);
    const fixed = Pill('EN · FR', tone: Tone.good);
    final remind = widget.setup.clinic['rules'] ?? const {};

    return PageFrame(
      eyebrow: 'Messages go by push first, then text or email if not opened',
      title: 'Notifications',
      children: [
        Columns(flex: const [3, 2], children: [
          Panel(
            title: 'What patients are told',
            child: SimpleTable(columns: const ['Message', 'When', 'Channels', 'Languages'], rows: [
              [const Text('Booking confirmation'), const Text('Immediately'), const Text('Push, then text, then email'), fixed],
              [const Text('Reminder, one-tap confirm'), Text(remind['remind48'] == false ? 'Off' : '48 h before'), const Text('Push, then email'), fixed],
              [const Text('Reminder, one-tap confirm'), Text(remind['remind24'] == false ? 'Off' : '24 h before'), const Text('Push, then text'), fr('reminder24')],
              [const Text('Intake form nudge'), const Text('24 h before if incomplete'), const Text('Push, then text'), fixed],
              [const Text('Waitlist offer'), const Text('On a freed time'), const Text('Push and text'), fixed],
              [const Text('Clinic announcement'), const Text('Manual'), const Text('Push, then email'), fixed],
              [const Text('Cancellation, patient cancelled'), const Text('Immediately'), const Text('Push, then text'), fr('cancelPatient')],
              [const Text('Cancellation, clinic cancelled'), const Text('Manual, staff pick a reason'), const Text('Text and email'), fr('cancelClinic')],
              [const Text('Missed visit follow-up'), const Text('Manual, from Missed visits'), const Text('Text, then email'), fr('missed')],
            ]),
          ),
          Panel(
            title: 'Message wording',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                initialValue: _pick,
                decoration: const InputDecoration(labelText: 'Template'),
                items: [for (final e in messageTemplates.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1))],
                onChanged: (v) => setState(() {
                  _pick = v!;
                  _load();
                }),
              ),
              const SizedBox(height: 12),
              TextField(controller: _en, maxLines: 5, minLines: 3, decoration: const InputDecoration(labelText: 'English'), onChanged: (_) => setState(() {})),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(_count(_en.text), style: t.bodySmall)),
              const SizedBox(height: 12),
              TextField(controller: _fr, maxLines: 5, minLines: 3, decoration: const InputDecoration(labelText: 'Français', hintText: 'Patients who chose French get this wording'), onChanged: (_) => setState(() {})),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(_fr.text.isEmpty ? 'Not translated: French-speaking patients get the English text.' : _count(_fr.text), style: t.bodySmall?.copyWith(color: _fr.text.isEmpty ? c.warn : null))),
              const SizedBox(height: 12),
              Text('Placeholders: {first_name} {service} {clinician} {date} {time} {clinic} {link} {reason}', style: t.bodySmall),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: () => act(context, () => d.saveTemplate(_pick, en: _en.text.trim(), fr: _fr.text.trim()), done: '${messageTemplates[_pick]!.$1} saved'),
                  child: const Text('Save wording'),
                ),
              ),
            ]),
          ),
        ]),
        Panel(
          title: 'Clinic announcement',
          note: 'Shows on the home screen of every patient of the clinic, and goes by push, then email, to everyone with a visit this week.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (notice != null && notice.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Expanded(child: Text('Showing now: $notice', style: t.bodyMedium)),
                  TextButton(onPressed: () => act(context, d.clearAnnouncement, done: 'Announcement removed from the patient app'), child: const Text('Remove')),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: TextField(controller: _announce, decoration: const InputDecoration(labelText: 'Message to patients', hintText: 'e.g. Parking lot B is closed this week.'))),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  if (_announce.text.trim().isEmpty) return say(context, 'Write the announcement first');
                  final text = _announce.text;
                  _announce.clear();
                  act(context, () => d.announce(text), done: 'Announcement posted. It shows in the patient app now.');
                },
                child: const Text('Send to patients'),
              ),
            ]),
          ]),
        ),
        Panel(
          title: 'Delivery log',
          note: 'Every message: when, to whom and how. Sending starts when Cloud Functions are on; until then messages wait here.',
          child: SimpleTable(
            columns: const ['Time', 'To', 'Message', 'Channel', 'Status'],
            empty: 'No messages yet.',
            rows: [
              for (final m in d.outbox.take(60))
                [
                  Text(m.at == null ? 'now' : '${shortDate(isoDate(m.at!))}, ${TimeOfDay.fromDateTime(m.at!).format(context)}', style: t.bodySmall),
                  Text(m.to),
                  Text(m.message),
                  Text(m.channel, style: t.bodySmall),
                  m.status == 'queued' ? const Pill('Waiting to send', tone: Tone.warn) : Pill(m.status, tone: m.status == 'delivered' ? Tone.good : Tone.mute),
                ],
            ],
          ),
        ),
      ],
    );
  }
}
