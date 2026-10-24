import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import '../ui.dart';

/// Who can do what, the team and their roles, and invitations.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _name = TextEditingController(), _email = TextEditingController();
  String _role = 'frontdesk';
  String? _clinician, _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final s = widget.setup;
    final email = _email.text.trim().toLowerCase();
    final err = _name.text.trim().isEmpty
        ? 'Enter their name.'
        : !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
            ? 'Enter their work email.'
            : widget.desk.staff.any((x) => x.email == email)
                ? '$email already works here.'
                : _role == 'clinician' && (_clinician ?? s.clinicians.firstOrNull?.id) == null
                    ? 'Add the clinician under Services & clinicians first.'
                    : null;
    setState(() => _error = err);
    if (err != null) return;
    final name = _name.text.trim();
    await act(context, () async {
      await s.invite(name: name, email: email, role: _role, clinicianId: _clinician ?? s.clinicians.firstOrNull?.id);
      await widget.desk.record('user.invite', email, '$name · ${staffRoles[_role]}');
    }, done: 'Invitation for $name saved');
    _name.clear();
    _email.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.setup, d = widget.desk, t = Theme.of(context).textTheme, c = CfColors.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => PageFrame(
        title: 'Users & roles',
        children: [
          const Panel(title: 'What each role can do', child: _Matrix()),
          Panel(
            title: 'Team',
            note: 'Every role change is written to the audit log. Nobody can change or remove their own role.',
            child: SimpleTable(
              columns: const ['Name', 'Email', 'Role', 'Is clinician', ''],
              rows: [
                for (final m in d.staff)
                  [
                    Text('${m.name}${m.uid == d.me.uid ? ' (you)' : ''}', style: t.labelLarge),
                    Text(m.email, style: t.bodySmall),
                    SizedBox(
                      width: 160,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('${m.uid}${m.role}'),
                        initialValue: m.role,
                        isDense: true,
                        decoration: InputDecoration(labelText: 'Role for ${m.name.split(' ').first}', floatingLabelBehavior: FloatingLabelBehavior.never),
                        items: [for (final e in staffRoles.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                        onChanged: m.uid == d.me.uid ? null : (v) => act(context, () => d.setRole(m, v!), done: '${m.name} is now ${staffRoles[v]}'),
                      ),
                    ),
                    m.role != 'clinician'
                        ? Text('—', style: t.bodySmall)
                        : SizedBox(
                            width: 170,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('${m.uid}${m.clinicianId}'),
                              initialValue: s.clinicians.any((x) => x.id == m.clinicianId) ? m.clinicianId : null,
                              isDense: true,
                              hint: Text('Choose', style: TextStyle(color: c.warn)),
                              items: [for (final x in s.clinicians) DropdownMenuItem(value: x.id, child: Text(x.short.isEmpty ? x.name : x.short))],
                              onChanged: m.uid == d.me.uid ? null : (v) => act(context, () => d.linkClinician(m, v), done: 'Saved'),
                            ),
                          ),
                    RowActions([
                      if (m.uid != d.me.uid)
                        small('Remove', () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Remove ${m.name}?'),
                              content: const Text('They lose access to this clinic straight away. Their past actions stay in the audit log.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
                                FilledButton(style: FilledButton.styleFrom(backgroundColor: c.crit), onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
                              ],
                            ),
                          );
                          if (ok == true && context.mounted) await act(context, () => d.removeStaff(m), done: '${m.name} removed');
                        }, danger: true),
                    ]),
                  ],
              ],
            ),
          ),
          Panel(
            title: 'Invitations',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SimpleTable(
                columns: const ['Name', 'Email', 'Role', ''],
                empty: 'No invitations waiting.',
                rows: [
                  for (final i in s.invites)
                    [
                      Text(i.name),
                      Text(i.email, style: t.bodySmall),
                      Text('${staffRoles[i.role] ?? i.role}${i.clinicianId == null ? '' : ' (${s.clinicians.where((x) => x.id == i.clinicianId).firstOrNull?.short ?? ''})'}'),
                      RowActions([small('Cancel', () => act(context, () => s.removeInvite(i.id), done: 'Invitation for ${i.name} cancelled'), danger: true)]),
                    ],
                ],
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(width: 200, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name'))),
                SizedBox(width: 240, child: TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Work email'))),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [for (final e in staffRoles.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => _role = v!),
                  ),
                ),
                if (_role == 'clinician')
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: _clinician ?? s.clinicians.firstOrNull?.id,
                      decoration: const InputDecoration(labelText: 'Which clinician'),
                      items: [for (final x in s.clinicians) DropdownMenuItem(value: x.id, child: Text(x.short.isEmpty ? x.name : x.short))],
                      onChanged: (v) => setState(() => _clinician = v),
                    ),
                  ),
                FilledButton.icon(onPressed: _invite, icon: const Icon(Icons.person_add_alt), label: const Text('Invite')),
              ]),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: t.bodyMedium?.copyWith(color: c.crit))),
              const SizedBox(height: 10),
              Text(
                'The invitation email comes with Cloud Functions. Until then, ask them to create an account on this site with that email address. Once they verify it, they can join ${s.clinic['name']} in the role you chose.',
                style: t.bodySmall?.copyWith(color: c.warn),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Matrix extends StatelessWidget {
  const _Matrix();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget chip(String v) => switch (v) {
          'RW' => const Pill('Change', tone: Tone.good),
          '—' => Text('—', style: t.bodySmall),
          _ => Pill(v, tone: Tone.info),
        };
    const rows = [
      ('Full calendar, all clinicians', 'RW', 'RW', 'Own', '—'),
      ('Live queue, check-in actions', 'RW', 'RW', 'Own', 'View'),
      ('Patient contact details', 'RW', 'RW', 'View', '—'),
      ('Intake form answers', 'View', 'View', 'Own', '—'),
      ('Waitlist and offers', 'RW', 'RW', '—', '—'),
      ('Services, hours, rules', 'RW', '—', '—', '—'),
      ('Users, roles, audit log', 'RW', '—', '—', '—'),
      ('Reports', 'RW', 'Today', 'Own', '—'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SimpleTable(columns: const ['Area', 'Admin', 'Front desk', 'Clinician', 'Support'], rows: [
        for (final r in rows) [Text(r.$1), chip(r.$2), chip(r.$3), chip(r.$4), chip(r.$5)],
      ]),
      const SizedBox(height: 8),
      Text('Patients have a fifth role, limited to their own record. The security rules enforce these limits, not just the screens.', style: t.bodySmall),
    ]);
  }
}
