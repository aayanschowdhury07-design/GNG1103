import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'ui.dart';

enum _Show {
  pending('Waiting for review'),
  approved('Approved'),
  rejected('Not approved'),
  draft('Still setting up');

  const _Show(this.label);
  final String label;
}

const _reasons = [
  'We couldn’t confirm the clinic at this address.',
  'The phone number didn’t answer as this clinic.',
  'The name or services don’t match a clinic we could find.',
  'This looks like a duplicate of a clinic already on ClinicFlow.',
];

/// The ClinicFlow team's page: new clinics waiting for review, with what they entered in setup
/// and who set them up. Approving lets patients find and book a clinic; "Not approved" sends it
/// back with a note the clinic sees on its staff website.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.setup});
  final ClinicSetup setup;
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  _Show _show = _Show.pending;

  @override
  Widget build(BuildContext context) {
    final review = widget.setup.review!, c = CfColors.of(context), t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(8)),
            child: Text('CF', style: t.labelMedium?.copyWith(color: c.heroFg)),
          ),
          const SizedBox(width: 12),
          const Flexible(child: Text('ClinicFlow · clinic review', overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          if (MediaQuery.sizeOf(context).width > 700) Text(review.email, style: t.bodySmall),
          TextButton(onPressed: widget.setup.signOut, child: const Text('Sign out')),
          const SizedBox(width: 12),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: c.line)),
      ),
      body: ListenableBuilder(
        listenable: review,
        builder: (context, _) {
          final shown = review.clinics.where((x) => x.approval == _show.name).toList();
          int count(_Show s) => review.clinics.where((x) => x.approval == s.name).length;
          return PageFrame(
            eyebrow: 'Patients can find and book a clinic only after it’s approved here',
            title: 'Clinics',
            actions: [
              SegmentedButton<_Show>(
                showSelectedIcon: false,
                segments: [for (final s in _Show.values) ButtonSegment(value: s, label: Text('${s.label} (${count(s)})'))],
                selected: {_show},
                onSelectionChanged: (v) => setState(() => _show = v.first),
              ),
            ],
            children: [
              if (_show == _Show.pending)
                Panel(
                  title: 'Before approving, check that',
                  child: Text(
                    '1. The clinic is real and at this address: search its name and address.\n'
                    '2. The phone number answers as this clinic.\n'
                    '3. The person who set it up works there: call the clinic and ask for them, or check their email matches the clinic’s website.',
                    style: t.bodyMedium?.copyWith(height: 1.6),
                  ),
                ),
              if (shown.isEmpty)
                Text(
                  switch (_show) {
                    _Show.pending => 'Nothing waiting. New clinics appear here when they finish setup.',
                    _Show.approved => 'No approved clinics yet.',
                    _Show.rejected => 'No clinics sent back.',
                    _Show.draft => 'No clinics part-way through setup.',
                  },
                  style: t.bodySmall,
                ),
              for (final x in shown) _ClinicCard(review: review, clinic: x),
            ],
          );
        },
      ),
    );
  }
}

String _when(DateTime? d) => d == null ? '—' : '${shortDate(isoDate(d))}, ${formatTime(d.hour * 60 + d.minute)}';

class _ClinicCard extends StatelessWidget {
  const _ClinicCard({required this.review, required this.clinic});
  final ClinicReview review;
  final ReviewClinic clinic;

  Future<void> _reject(BuildContext context) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(clinic.approval == 'approved' ? 'Withdraw approval for ${clinic.name}?' : 'Not approve ${clinic.name}?'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tell the clinic what to fix. They see this on their staff website and can resubmit.'),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in _reasons) ActionChip(label: Text(r), onPressed: () => set(() => note.text = r)),
              ]),
              const SizedBox(height: 12),
              TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Note to the clinic'), onChanged: (_) => set(() {})),
              if (clinic.approval == 'approved') ...[
                const SizedBox(height: 8),
                Text('Patients stop finding it and can’t book it online. Visits already booked stay booked.', style: Theme.of(context).textTheme.bodySmall),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: CfColors.of(context).crit),
              onPressed: note.text.trim().isEmpty ? null : () => Navigator.pop(context, true),
              child: const Text('Send back'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) await act(context, () => review.reject(clinic, note.text), done: '${clinic.name} sent back with your note');
    note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, c = CfColors.of(context);
    Widget line(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(label, style: t.bodySmall)),
            Expanded(child: value),
          ]),
        );
    final status = switch (clinic.approval) {
      'pending' => const Pill('Waiting for review', tone: Tone.warn),
      'approved' => const Pill('Approved', tone: Tone.good),
      'rejected' => const Pill('Not approved', tone: Tone.crit),
      _ => const Pill('Setting up'),
    };
    return Panel(
      title: clinic.name.isEmpty ? '(no name yet)' : clinic.name,
      trailing: status,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        line('Submitted', Text(_when(clinic.submittedAt))),
        if (clinic.reviewedAt != null) line('Last decision', Text(_when(clinic.reviewedAt))),
        if (clinic.note.isNotEmpty) line('Note sent', Text(clinic.note, style: t.bodyMedium?.copyWith(color: c.crit))),
        line('Address', Text(clinic.address.isEmpty ? 'Not given' : clinic.address)),
        line(
          'Map pin',
          clinic.lat == null
              ? const Text('Not set')
              : Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                    onPressed: () => web.window.open('https://www.openstreetmap.org/?mlat=${clinic.lat}&mlon=${clinic.lng}#map=17/${clinic.lat}/${clinic.lng}', '_blank'),
                    child: Text('${clinic.lat!.toStringAsFixed(4)}, ${clinic.lng!.toStringAsFixed(4)} · open the map'),
                  ),
                ),
        ),
        line('Phone', SelectableText(clinic.phone.isEmpty ? 'Not given' : clinic.phone)),
        line('Kind of care', Text(clinic.kind.isEmpty ? 'Not given' : clinic.kind)),
        line('Directory', Text(clinic.listed ? 'Wants to be listed' : 'Booking link only')),
        FutureBuilder<ReviewDetails>(
          future: review.details(clinic),
          builder: (context, snap) {
            final d = snap.data;
            if (snap.hasError) return line('Set up by', Text('Couldn’t load: ${snap.error}', style: t.bodySmall?.copyWith(color: c.crit)));
            if (d == null) return line('Set up by', const Text('Loading…'));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              line('Set up by', SelectableText('${d.ownerName.isEmpty ? 'Unknown' : d.ownerName} · ${d.ownerEmail}')),
              line('Services', Text(d.services.isEmpty ? 'None yet' : d.services.join('\n'))),
              line('Clinicians', Text(d.clinicians.isEmpty ? 'None yet' : d.clinicians.join('\n'))),
            ]);
          },
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (clinic.approval == 'pending' || clinic.approval == 'rejected')
            FilledButton(
              onPressed: () => act(context, () => review.approve(clinic), done: '${clinic.name} approved. Patients can find and book it now.'),
              child: const Text('Approve'),
            ),
          if (clinic.approval == 'pending') OutlinedButton(onPressed: () => _reject(context), child: const Text('Not approved…')),
          if (clinic.approval == 'approved') OutlinedButton(onPressed: () => _reject(context), child: const Text('Withdraw approval…')),
          if (clinic.approval == 'draft') Text('Approval opens once they finish setup.', style: t.bodySmall),
        ]),
      ]),
    );
  }
}
