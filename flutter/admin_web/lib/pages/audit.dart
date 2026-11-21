import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../csv.dart';
import '../l10n.dart';
import '../ui.dart';

String _stamp(BuildContext context, DateTime? at) => at == null ? tr('now') : '${shortDate(isoDate(at), lang: lang)}, ${TimeOfDay.fromDateTime(at).format(context)}';

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
      title: tr('Audit log'),
      actions: [
        SizedBox(width: 240, child: TextField(decoration: InputDecoration(labelText: tr('Filter'), hintText: tr('Person, patient or action'), isDense: true), onChanged: (v) => setState(() => _q = v))),
        OutlinedButton(
          style: smallButton,
          onPressed: () {
            downloadCsv('clinicflow-audit.csv', [
              ['Time', 'Actor', 'Action', 'Record', 'Detail'],
              for (final a in rows) [a.at?.toIso8601String() ?? '', a.actor, a.action, a.record, a.detail],
            ]);
            d.record('export.csv', 'audit', '${rows.length} rows');
          },
          child: Text(tr('Export CSV')),
        ),
      ],
      children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('{shown} of {total} entries', {'shown': rows.length, 'total': d.audit.length}), style: t.bodySmall),
            const SizedBox(height: 8),
            SimpleTable(
              columns: [tr('Time'), tr('Who'), tr('Action'), tr('Record'), tr('Detail')],
              empty: q.isEmpty ? tr('Nothing recorded yet.') : tr('No entries match “{q}”.', {'q': _q}),
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
      ],
    );
  }
}
