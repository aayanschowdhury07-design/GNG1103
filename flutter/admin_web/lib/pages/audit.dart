import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../csv.dart';
import '../ui.dart';

String _stamp(BuildContext context, DateTime? at) => at == null ? 'now' : '${shortDate(isoDate(at))}, ${TimeOfDay.fromDateTime(at).format(context)}';

/// Every booking, change, export and message, newest first. Entries can't be edited or deleted.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key, required this.desk});
  final ClinicDesk desk;
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme, d = widget.desk;
    final q = _q.toLowerCase();
    final rows = d.audit.where((a) => q.isEmpty || '${a.actor} ${a.action} ${a.record} ${a.detail}'.toLowerCase().contains(q)).toList();
    return PageFrame(
      eyebrow: 'Append-only · each entry stamped with the server’s time and its author · hosted in Canada',
      title: 'Audit log',
      actions: [
        SizedBox(width: 240, child: TextField(decoration: const InputDecoration(labelText: 'Filter', hintText: 'Person, patient or action', isDense: true), onChanged: (v) => setState(() => _q = v))),
        OutlinedButton(
          style: smallButton,
          onPressed: () {
            downloadCsv('clinicflow-audit.csv', [
              ['Time', 'Actor', 'Action', 'Record', 'Detail'],
              for (final a in rows) [a.at?.toIso8601String() ?? '', a.actor, a.action, a.record, a.detail],
            ]);
            d.record('export.csv', 'audit', '${rows.length} rows');
          },
          child: const Text('Export CSV'),
        ),
      ],
      children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${rows.length} of ${d.audit.length} recent entries · every booking, change and message from the staff website is recorded here', style: t.bodySmall),
            const SizedBox(height: 8),
            SimpleTable(
              columns: const ['Time', 'Who', 'Action', 'Record', 'Detail'],
              empty: q.isEmpty ? 'Nothing recorded yet.' : 'No entries match “$_q”.',
              rows: [
                for (final a in rows.take(300))
                  [
                    Text(_stamp(context, a.at), style: t.bodySmall),
                    Text(a.actor),
                    Text(a.action, style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
                    Text(a.record, style: t.bodySmall),
                    ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(a.detail, style: t.bodySmall)),
                  ],
              ],
            ),
          ]),
        ),
        Text('Patient-app actions (online bookings, cancellations, check-ins) join this log when booking moves to Cloud Functions.', style: t.bodySmall),
      ],
    );
  }
}
