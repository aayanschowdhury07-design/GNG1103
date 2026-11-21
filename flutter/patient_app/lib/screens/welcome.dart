import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

import '../role_choice.dart';
import '../scope.dart';

/// The first screen: patient or clinic staff. Patients go on to the app; staff open the staff app.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onPatient});
  final VoidCallback onPatient;

  @override
  Widget build(BuildContext context) {
    final s = context.s, c = CfColors.of(context), t = Theme.of(context).textTheme;
    Widget option({required IconData icon, required String title, required String sub, required VoidCallback onTap}) => Material(
          color: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Container(width: 48, height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: c.accent)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: t.titleMedium),
                    const SizedBox(height: 2),
                    Text(sub, style: t.bodySmall),
                  ]),
                ),
                Icon(Icons.chevron_right, color: c.muted),
              ]),
            ),
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(10)), child: Text('CF', style: t.labelLarge?.copyWith(color: c.heroFg, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 10),
                  Text('ClinicFlow', style: t.headlineSmall),
                ]),
                const SizedBox(height: 28),
                Text(s.t('welcomeTitle'), textAlign: TextAlign.center, style: t.headlineMedium),
                const SizedBox(height: 8),
                Text(s.t('welcomeSub'), textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: c.muted)),
                const SizedBox(height: 28),
                option(
                  icon: Icons.favorite_outline,
                  title: s.t('rolePatient'),
                  sub: s.t('rolePatientSub'),
                  onTap: () {
                    saveRole('patient');
                    onPatient();
                  },
                ),
                const SizedBox(height: 12),
                option(
                  icon: Icons.medical_services_outlined,
                  title: s.t('roleStaff'),
                  sub: s.t('roleStaffSub'),
                  onTap: () {
                    saveRole('staff');
                    openStaffApp();
                  },
                ),
                const SizedBox(height: 18),
                Text(s.t('roleChangeLater'), textAlign: TextAlign.center, style: t.bodySmall),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () => context.session.setLang(s.fr ? 'en' : 'fr'),
                    child: Text(s.fr ? 'English' : 'Français'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
