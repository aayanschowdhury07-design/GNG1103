import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

import '../scope.dart';
import '../widgets.dart';
import 'account.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _editDetails(BuildContext context) async {
    final b = context.backend, s = context.s;
    final details = await showDialog<(String, String)>(context: context, builder: (_) => _DetailsDialog(name: b.profile?.name ?? '', email: b.profile?.email ?? ''));
    if (details == null || details.$1.trim().isEmpty) return;
    await b.saveProfile(name: details.$1, email: details.$2);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('saved'))));
  }

  Future<void> _askDelete(BuildContext context) async {
    final s = context.s, c = context.colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('deleteAsk')),
        content: Text(s.t('deleteNote')),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancelWord'))),
          TextButton(style: TextButton.styleFrom(foregroundColor: c.crit), onPressed: () => Navigator.pop(context, true), child: Text(s.t('deleteWord'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.backend.requestMyData('delete');
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('deleteSent'))));
  }

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final p = context.session, b = context.backend, s = context.s, me = b.profile;
      void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      final name = me?.name ?? '';
      return ScreenFrame(
        back: false,
        title: s.t('profileTitle'),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Avatar(name.isEmpty ? '?' : initials(name)),
            title: Text(name.isEmpty ? s.t('addName') : name),
            subtitle: Text([phoneText(me?.phone ?? ''), me?.email ?? ''].where((x) => x.isNotEmpty).join(' · ')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editDetails(context),
          ),
          Section(
            child: Column(children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('language')),
                subtitle: Text(s.t('langNote')),
                trailing: SizedBox(width: 120, child: UnderlineTabs<String>(label: 'Language / Langue', options: const [('en', 'EN'), ('fr', 'FR')], selected: p.lang, onSelect: p.setLang)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('smsTitle')),
                subtitle: Text(b.smsConsent
                    ? s.t('smsOnGiven', {'date': recordDate(b.smsConsentChangedOn, lang: context.lang)})
                    : b.smsConsentChangedOn.isEmpty
                        ? s.t('smsOffNever')
                        : s.t('smsOffSince', {'date': recordDate(b.smsConsentChangedOn, lang: context.lang)})),
                value: b.smsConsent,
                onChanged: (on) {
                  b.setSmsConsent(on);
                  snack(s.t(on ? 'smsOnSnack' : 'smsOffSnack'));
                },
              ),
              ListTile(contentPadding: EdgeInsets.zero, title: Text(s.t('push')), subtitle: Text(s.t('pushSub')), trailing: Text(s.t('on'))),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(s.t('largeText')), subtitle: Text(s.t('largeTextSub')), value: p.largeText, onChanged: p.setLargeText),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(s.t('darkMode')), value: p.themeMode == ThemeMode.dark, onChanged: p.setDark),
            ]),
          ),
          Section(
            child: Column(children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('family')),
                subtitle: Text(s.t('familySub')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(const FamilyScreen()),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('history')),
                subtitle: Text('${s.t('pastVisits', {'n': '${b.visitHistory().length}'})}${b.balanceOwing > 0 ? ' · ${s.t('owing', {'amount': s.money(b.balanceOwing)})}' : ''}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(const HistoryScreen()),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('dataCopy')),
                subtitle: Text(s.t('dataSub')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await b.requestMyData('export');
                  snack(s.t('dataCopySent'));
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('deleteAccount')),
                subtitle: Text(s.t('deleteSub')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _askDelete(context),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: b.signOut, child: Text(s.t('signOut'))),
        ],
      );
    });
  }
}

/// The patient's name and email; closes with the new values, or nothing on cancel.
class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.name, required this.email});
  final String name, email;
  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  late final _name = TextEditingController(text: widget.name), _email = TextEditingController(text: widget.email);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return AlertDialog(
      title: Text(s.t('yourDetails')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _name, autofocus: true, decoration: InputDecoration(labelText: s.t('fullName')), autofillHints: const [AutofillHints.name], textCapitalization: TextCapitalization.words),
        const SizedBox(height: 12),
        TextField(controller: _email, decoration: InputDecoration(labelText: s.t('email')), keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancelWord'))),
        FilledButton(onPressed: () => Navigator.pop(context, (_name.text, _email.text)), child: Text(s.t('save'))),
      ],
    );
  }
}
