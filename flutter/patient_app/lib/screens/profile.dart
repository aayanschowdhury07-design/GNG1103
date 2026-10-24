import 'package:flutter/material.dart';

import '../scope.dart';
import '../widgets.dart';
import 'account.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final p = context.session, b = context.backend;
      void open(Widget s) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => s));
      void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      return ScreenFrame(
        back: false,
        title: 'Profile',
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Avatar(initials(p.name)),
            title: Text(p.name),
            subtitle: Text('${p.phone} · signed in with Face ID'),
          ),
          Section(
            child: Column(children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Language'),
                subtitle: const Text('Booking and check-in are in French. Other screens follow in the translation pass.'),
                trailing: SizedBox(width: 120, child: UnderlineTabs<String>(label: 'Language / Langue', options: const [('en', 'EN'), ('fr', 'FR')], selected: p.lang, onSelect: p.setLang)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Text reminders'),
                subtitle: Text(b.smsConsent ? 'On · consent given ${b.smsConsentChangedOn}' : 'Off since ${b.smsConsentChangedOn} · we use push and email'),
                value: b.smsConsent,
                onChanged: (on) {
                  b.setSmsConsent(on);
                  snack(on ? 'Text reminders on' : 'Text reminders off. We will use push and email.');
                },
              ),
              const ListTile(contentPadding: EdgeInsets.zero, title: Text('Push notifications'), subtitle: Text('Reminders, waitlist offers, notices'), trailing: Text('On')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Large text'), subtitle: const Text('Makes everything in the app bigger'), value: p.largeText, onChanged: p.setLargeText),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Dark mode'), value: p.themeMode == ThemeMode.dark, onChanged: p.setDark),
            ]),
          ),
          Section(
            child: Column(children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Family members'),
                subtitle: const Text('Book for someone you care for'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(const FamilyScreen()),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Visit history & receipts'),
                subtitle: Text('${b.visitHistory().length} past visits${b.balanceOwing > 0 ? ' · \$${b.balanceOwing.toStringAsFixed(0)} owing' : ''}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(const HistoryScreen()),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Download my data / delete account'),
                subtitle: const Text('PIPEDA request'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => snack('Request sent. Your data file arrives by email within 30 days.'),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: b.signOut, child: const Text('Sign out')),
        ],
      );
    });
  }
}
