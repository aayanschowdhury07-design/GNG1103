import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'patient_link.dart';
import 'portal_theme.dart';
import 'ui.dart';

/// Who's signed in, what their role can do, the language, and Sign out.
class AccountTab extends StatelessWidget {
  const AccountTab({super.key, required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;

  static const _can = {
    'admin': ['See today, the queue and every clinician’s schedule', 'Check patients in and run the queue', 'Book walk-ins, text and remind patients', 'Offer freed times to the waitlist', 'Everything else on the staff website'],
    'frontdesk': ['See today, the queue and every clinician’s schedule', 'Check patients in and run the queue', 'Book walk-ins, text and remind patients', 'Offer freed times to the waitlist'],
    'clinician': ['See your own patients and schedule', 'Call your patients in and complete visits'],
    'support': ['See the live queue', 'View visits, without changing them'],
  };

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme, me = desk.me;
    final name = me.name.isEmpty ? me.email : me.name;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
      Text(tr('Account'), style: t.headlineMedium?.copyWith(fontSize: 30)),
      const SizedBox(height: 18),
      Row(children: [
        CircleAvatar(radius: 28, backgroundColor: Portal.navy, child: Text(initialsOf(name), style: t.titleMedium?.copyWith(color: Colors.white))),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: t.titleMedium),
            Text('${tr(staffRoles[me.role] ?? me.role)} · ${setup.clinic['name'] ?? ''}', style: t.bodySmall),
            if (me.name.isNotEmpty) Text(me.email, style: t.bodySmall),
          ]),
        ),
      ]),
      SectionHead(tr('What your role can do')),
      for (final line in _can[me.role] ?? const <String>[])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check, size: 18, color: c.good),
            const SizedBox(width: 10),
            Expanded(child: Text(tr(line), style: t.bodyMedium)),
          ]),
        ),
      SectionHead(tr('Language')),
      const SizedBox(height: 12),
      ValueListenableBuilder<String>(
        valueListenable: staffLang,
        builder: (context, code, _) => SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'fr', label: Text('Français'))],
          selected: {code},
          onSelectionChanged: (v) => staffLang.value = v.first,
        ),
      ),
      const SizedBox(height: 32),
      OutlinedButton.icon(onPressed: setup.signOut, icon: const Icon(Icons.logout, size: 18), label: Text(tr('Sign out'))),
      if (canOpenPatientApp) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            await setup.signOut();
            openPatientApp();
          },
          child: Text(tr('Switch to the patient app')),
        ),
      ],
      const SizedBox(height: 12),
      Text(tr('Settings, services, users and reports are on the staff website.'), style: t.bodySmall, textAlign: TextAlign.center),
    ]);
  }
}
