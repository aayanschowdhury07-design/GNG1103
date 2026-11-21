import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
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
    return segments > 1
        ? tr('{chars} characters before {placeholders} are filled · {segments} text segments (costs more per message)', {'chars': text.length, 'segments': segments})
        : tr('{chars} characters before {placeholders} are filled · 1 text segment', {'chars': text.length});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context), d = widget.desk;
    final notice = widget.setup.clinic['notice'] as String?;
    Widget fr(String k) => d.template(k, 'fr').isEmpty ? Pill(tr('FR missing'), tone: Tone.warn) : const Pill('EN · FR', tone: Tone.good);
    const fixed = Pill('EN · FR', tone: Tone.good);
    final remind = widget.setup.clinic['rules'] ?? const {};

    return PageFrame(
      title: tr('Notifications'),
      children: [
        Columns(flex: const [3, 2], children: [
          Panel(
            title: tr('What patients are told'),
            child: SimpleTable(columns: [tr('Message'), tr('When'), tr('Channels'), tr('Languages')], rows: [
              [Text(tr('Booking confirmation')), Text(tr('Immediately')), Text(tr('Push, then text, then email')), fixed],
              [Text(tr('Reminder, one-tap confirm')), Text(remind['remind48'] == false ? tr('Off') : tr('48 h before')), Text(tr('Push, then email')), fixed],
              [Text(tr('Reminder, one-tap confirm')), Text(remind['remind24'] == false ? tr('Off') : tr('24 h before')), Text(tr('Push, then text')), fr('reminder24')],
              [Text(tr('Intake form nudge')), Text(tr('24 h before if incomplete')), Text(tr('Push, then text')), fixed],
              [Text(tr('Waitlist offer')), Text(tr('On a freed time')), Text(tr('Push and text')), fixed],
              [Text(tr('Clinic announcement')), Text(tr('Manual')), Text(tr('Push, then email')), fixed],
              [Text(tr('Cancellation, patient cancelled')), Text(tr('Immediately')), Text(tr('Push, then text')), fr('cancelPatient')],
              [Text(tr('Cancellation, clinic cancelled')), Text(tr('Manual, staff pick a reason')), Text(tr('Text and email')), fr('cancelClinic')],
              [Text(tr('Missed visit follow-up')), Text(tr('Manual, from Missed visits')), Text(tr('Text, then email')), fr('missed')],
            ]),
          ),
          Panel(
            title: tr('Message wording'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                initialValue: _pick,
                decoration: InputDecoration(labelText: tr('Template')),
                items: [for (final e in messageTemplates.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value.$1)))],
                onChanged: (v) => setState(() {
                  _pick = v!;
                  _load();
                }),
              ),
              const SizedBox(height: 12),
              TextField(controller: _en, maxLines: 5, minLines: 3, decoration: const InputDecoration(labelText: 'English'), onChanged: (_) => setState(() {})),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(_count(_en.text), style: t.bodySmall)),
              const SizedBox(height: 12),
              TextField(controller: _fr, maxLines: 5, minLines: 3, decoration: InputDecoration(labelText: 'Français', hintText: tr('Patients who chose French get this wording')), onChanged: (_) => setState(() {})),
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(_fr.text.isEmpty ? tr('Not translated: French-speaking patients get the English text.') : _count(_fr.text), style: t.bodySmall?.copyWith(color: _fr.text.isEmpty ? c.warn : null))),
              const SizedBox(height: 12),
              Text('${tr('Placeholders:')} {first_name} {service} {clinician} {date} {time} {clinic} {link} {reason}', style: t.bodySmall),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: () => act(context, () => d.saveTemplate(_pick, en: _en.text.trim(), fr: _fr.text.trim()), done: tr('{template} saved', {'template': tr(messageTemplates[_pick]!.$1)})),
                  child: Text(tr('Save wording')),
                ),
              ),
            ]),
          ),
        ]),
        Panel(
          title: tr('Clinic announcement'),
          note: tr('Shows on the home screen of every patient of the clinic, and goes by push, then email, to everyone with a visit this week.'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (notice != null && notice.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Expanded(child: Text(tr('Showing now: {notice}', {'notice': notice}), style: t.bodyMedium)),
                  TextButton(onPressed: () => act(context, d.clearAnnouncement, done: tr('Announcement removed from the patient app')), child: Text(tr('Remove'))),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: TextField(controller: _announce, decoration: InputDecoration(labelText: tr('Message to patients'), hintText: tr('e.g. Parking lot B is closed this week.')))),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  if (_announce.text.trim().isEmpty) return say(context, tr('Write the announcement first'));
                  final text = _announce.text;
                  _announce.clear();
                  act(context, () => d.announce(text), done: tr('Announcement posted. It shows in the patient app now.'));
                },
                child: Text(tr('Send to patients')),
              ),
            ]),
          ]),
        ),
        Panel(
          title: tr('Delivery log'),
          child: SimpleTable(
            columns: [tr('Time'), tr('To'), tr('Message'), tr('Channel'), tr('Status')],
            empty: tr('No messages yet.'),
            rows: [
              for (final m in d.outbox.take(60))
                [
                  Text(m.at == null ? tr('now') : '${shortDate(isoDate(m.at!), lang: lang)}, ${TimeOfDay.fromDateTime(m.at!).format(context)}', style: t.bodySmall),
                  Text(m.to),
                  Text(m.message),
                  Text(m.channel, style: t.bodySmall),
                  _status(m.status),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

/// How a message went, as the sendQueued Cloud Function records it.
Widget _status(String s) => switch (s) {
      'queued' => Pill(tr('Waiting to send'), tone: Tone.warn),
      'sent' || 'delivered' => Pill(tr('Sent'), tone: Tone.good),
      'sent (test)' => Pill(tr('Sent (test copy)'), tone: Tone.good),
      'failed' => Pill(tr('Failed'), tone: Tone.crit),
      _ => Pill(tr('Not sent'), tone: Tone.mute),
    };
