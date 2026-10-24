import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'pages/audit.dart';
import 'pages/calendar.dart';
import 'pages/clinic.dart';
import 'pages/dashboard.dart';
import 'pages/kiosk.dart';
import 'pages/missed.dart';
import 'pages/notifications.dart';
import 'pages/queue.dart';
import 'pages/reports.dart';
import 'pages/users.dart';
import 'pages/waitlist.dart';
import 'ui.dart';
import 'wizard.dart';

enum StaffPage {
  dash('Dashboard', Icons.space_dashboard_outlined),
  cal('Calendar', Icons.calendar_month_outlined),
  queue('Live queue', Icons.groups_outlined),
  kiosk('Check-in tablet', Icons.tablet_mac_outlined),
  wait('Waitlist & recovery', Icons.playlist_add_check),
  missed('Missed visits', Icons.event_busy_outlined),
  services('Services & clinicians', Icons.medical_services_outlined),
  notif('Notifications', Icons.notifications_none),
  users('Users & roles', Icons.manage_accounts_outlined),
  audit('Audit log', Icons.shield_outlined),
  reports('Reports', Icons.bar_chart),
  setup('Setup wizard', Icons.settings_outlined);

  const StaffPage(this.label, this.icon);
  final String label;
  final IconData icon;

  /// The section heading shown above this page in the sidebar, if it starts one.
  String? get section => switch (this) { services => 'Clinic', audit => 'Trust', _ => null };
}

/// What each role can open (as in the prototype). The security rules enforce the same limits.
const pagesFor = {
  'admin': StaffPage.values,
  'frontdesk': [StaffPage.dash, StaffPage.cal, StaffPage.queue, StaffPage.kiosk, StaffPage.wait, StaffPage.missed, StaffPage.reports],
  'clinician': [StaffPage.dash, StaffPage.cal, StaffPage.queue, StaffPage.reports],
  'support': [StaffPage.queue],
};

/// The staff website once setup is done: sidebar on the left, the page on the right.
class StaffShell extends StatefulWidget {
  const StaffShell({super.key, required this.setup});
  final ClinicSetup setup;
  @override
  State<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<StaffShell> {
  StaffPage? _page;
  final _scaffold = GlobalKey<ScaffoldState>();

  /// Opens [p], and for the calendar, optionally starts a booking.
  void go(StaffPage p, {bool book = false}) {
    setState(() {
      _page = p;
      _startBooking = book;
    });
    if (_scaffold.currentState?.isDrawerOpen ?? false) Navigator.pop(context);
  }

  bool _startBooking = false;

  @override
  Widget build(BuildContext context) {
    final setup = widget.setup, desk = setup.desk!, me = setup.me!;
    final allowed = pagesFor[me.role] ?? const [StaffPage.queue];
    final page = allowed.contains(_page) ? _page! : allowed.first;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final side = _Sidebar(setup: setup, pages: allowed, current: page, onGo: go);
    final body = ListenableBuilder(
      listenable: Listenable.merge([setup, desk]),
      builder: (context, _) => Column(children: [
        if (desk.error != null) _Banner('Some clinic data couldn’t load. If this is the live project, deploy the latest security rules. (${desk.error})', tone: true),
        if (!setup.approved) _ReviewBanner(setup: setup, onSetup: () => go(StaffPage.setup)),
        if (me.readOnly) const _Banner('Read-only for your role. Ask an admin if you need to change something.'),
        Expanded(child: KeyedSubtree(key: ValueKey(page), child: _pageFor(page, setup, desk))),
      ]),
    );
    return Scaffold(
      key: _scaffold,
      drawer: wide ? null : Drawer(width: 280, child: side),
      appBar: wide
          ? null
          // the page shows its own title, so the bar names the clinic
          : AppBar(
              title: Text(setup.clinic['name'] ?? '', style: Theme.of(context).textTheme.titleMedium),
              leading: IconButton(tooltip: 'Menu', icon: const Icon(Icons.menu), onPressed: () => _scaffold.currentState?.openDrawer()),
            ),
      body: wide
          ? Row(children: [SizedBox(width: 260, child: side), Container(width: 1, color: CfColors.of(context).line), Expanded(child: body)])
          : body,
    );
  }

  Widget _pageFor(StaffPage p, ClinicSetup setup, ClinicDesk desk) {
    final book = _startBooking;
    _startBooking = false;
    return switch (p) {
      StaffPage.dash => DashboardPage(setup: setup, desk: desk, onGo: go),
      StaffPage.cal => CalendarPage(setup: setup, desk: desk, startBooking: book),
      StaffPage.queue => QueuePage(setup: setup, desk: desk, onGo: go),
      StaffPage.kiosk => KioskPage(setup: setup, desk: desk),
      StaffPage.wait => WaitlistPage(setup: setup, desk: desk),
      StaffPage.missed => MissedPage(setup: setup, desk: desk),
      StaffPage.services => ClinicPage(setup: setup, desk: desk),
      StaffPage.notif => NotificationsPage(setup: setup, desk: desk),
      StaffPage.users => UsersPage(setup: setup, desk: desk),
      StaffPage.audit => AuditPage(desk: desk),
      StaffPage.reports => ReportsPage(setup: setup, desk: desk),
      StaffPage.setup => WizardBody(setup: setup),
    };
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.setup, required this.pages, required this.current, required this.onGo});
  final ClinicSetup setup;
  final List<StaffPage> pages;
  final StaffPage current;
  final void Function(StaffPage) onGo;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final me = setup.me!;
    return Material(
      color: c.bg,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(8)),
                child: Text(setup.clinic['initials'] ?? '', style: t.labelMedium?.copyWith(color: c.heroFg)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(setup.clinic['name'] ?? '', style: t.titleMedium, overflow: TextOverflow.ellipsis),
                  Text('${(setup.clinic['city'] as String? ?? '').isEmpty ? '' : '${setup.clinic['city']} · '}single location', style: t.bodySmall, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [
              for (final p in pages) ...[
                if (p.section != null)
                  Padding(padding: const EdgeInsets.fromLTRB(12, 16, 12, 4), child: Text(p.section!.toUpperCase(), style: t.labelMedium?.copyWith(color: c.muted, letterSpacing: .6))),
                Semantics(
                  selected: p == current,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onGo(p),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: p == current ? c.accentSoft : null, borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        Icon(p.icon, size: 20, color: p == current ? c.accent : c.muted),
                        const SizedBox(width: 12),
                        Expanded(child: Text(p.label, style: t.bodyMedium?.copyWith(color: p == current ? c.accent : c.fg, fontWeight: p == current ? FontWeight.w600 : null))),
                      ]),
                    ),
                  ),
                ),
              ],
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(me.name.isEmpty ? me.email : me.name, style: t.labelLarge, overflow: TextOverflow.ellipsis),
                  Text(staffRoles[me.role] ?? me.role, style: t.bodySmall),
                ]),
              ),
              TextButton(onPressed: setup.signOut, child: const Text('Sign out')),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Where the clinic's ClinicFlow review stands, until it's approved.
class _ReviewBanner extends StatefulWidget {
  const _ReviewBanner({required this.setup, required this.onSetup});
  final ClinicSetup setup;
  final VoidCallback onSetup;
  @override
  State<_ReviewBanner> createState() => _ReviewBannerState();
}

class _ReviewBannerState extends State<_ReviewBanner> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.setup, c = CfColors.of(context), t = Theme.of(context).textTheme;
    final rejected = s.approval == 'rejected', admin = s.me?.isAdmin ?? false;
    final fg = rejected ? c.crit : c.accent;
    return Container(
      width: double.infinity,
      color: rejected ? c.critSoft : c.accentSoft,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(
          rejected
              ? 'ClinicFlow didn’t approve ${s.clinic['name']} yet${s.approvalNote.isEmpty ? '.' : ': ${s.approvalNote}'}'
              : 'ClinicFlow is reviewing ${s.clinic['name']}, usually within one business day. Until it’s approved, patients can’t find or book you online; your team can use the calendar meanwhile.',
          style: t.bodyMedium?.copyWith(color: fg),
        ),
        if (rejected && admin) ...[
          TextButton(onPressed: widget.onSetup, child: const Text('Update details')),
          FilledButton(
            style: smallFilled,
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await act(context, s.resubmit, done: 'Sent back to ClinicFlow for review');
                    if (mounted) setState(() => _busy = false);
                  },
            child: const Text('Resubmit'),
          ),
        ],
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text, {this.tone = false});
  final String text;
  final bool tone;
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context);
    return Container(
      width: double.infinity,
      color: tone ? c.critSoft : c.warnSoft,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tone ? c.crit : c.warn)),
    );
  }
}
