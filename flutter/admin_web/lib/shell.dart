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
import 'pages/settings.dart';
import 'pages/users.dart';
import 'pages/waitlist.dart';
import 'kiosk_lock.dart';
import 'logo_picker.dart';
import 'l10n.dart';
import 'portal_theme.dart';
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
  settings('Settings', Icons.tune),
  setup('Setup wizard', Icons.settings_outlined);

  const StaffPage(this.label, this.icon);
  final String label;
  final IconData icon;

  /// The section heading shown above this page in the sidebar, if it starts one.
  /// The optional feature (see clinicFeatures) this page belongs to, if any.
  String? get feature => switch (this) { kiosk => 'kiosk', wait => 'waitlist', missed => 'missed', _ => null };

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

  /// This browser is a locked check-in tablet: only the check-in screen shows, until the PIN.
  /// Kept across reloads so reloading never reveals the staff website.
  late bool _kioskLocked = KioskLock.lockedClinic == widget.setup.clinicId;

  void _lockKiosk() {
    KioskLock.lockedClinic = widget.setup.clinicId;
    setState(() => _kioskLocked = true);
    KioskLock.enterFullscreen();
  }

  void _unlockKiosk() {
    KioskLock.lockedClinic = null;
    KioskLock.exitFullscreen();
    setState(() {
      _kioskLocked = false;
      _page = StaffPage.kiosk;
    });
  }

  @override
  Widget build(BuildContext context) {
    final setup = widget.setup, desk = setup.desk!, me = setup.me!;
    // pages of features the clinic switched off in Settings are hidden
    final off = {for (final e in ((setup.clinic['features'] as Map?) ?? const {}).entries) if (e.value == false) '${e.key}'};
    final allowed = [for (final p in pagesFor[me.role] ?? const [StaffPage.queue]) if (p.feature == null || !off.contains(p.feature)) p];
    if (_kioskLocked && allowed.contains(StaffPage.kiosk)) {
      return Scaffold(body: KioskPage(setup: setup, desk: desk, locked: true, onUnlock: _unlockKiosk));
    }
    final page = allowed.contains(_page) ? _page! : allowed.first;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final side = ListenableBuilder(listenable: desk, builder: (context, _) => _Sidebar(setup: setup, desk: desk, pages: allowed, current: page, onGo: go));
    final body = ListenableBuilder(
      listenable: Listenable.merge([setup, desk]),
      builder: (context, _) => Column(children: [
        if (desk.error != null) _Banner(tr('Some clinic data couldn’t load. Try reloading the page.'), tone: true),
        if (!setup.approved) _ReviewBanner(setup: setup, onSetup: () => go(StaffPage.setup)),
        if (me.readOnly) _Banner(tr('Read-only for your role. Ask an admin if you need to change something.')),
        Expanded(child: KeyedSubtree(key: ValueKey(page), child: _pageFor(page, setup, desk))),
      ]),
    );
    return Scaffold(
      key: _scaffold,
      drawer: wide ? null : Drawer(width: 260, shape: const RoundedRectangleBorder(), child: side),
      appBar: wide
          ? null
          // the page shows its own title, so the bar names the clinic
          : AppBar(
              title: Text(setup.clinic['name'] ?? '', style: Theme.of(context).textTheme.titleMedium),
              leading: IconButton(tooltip: tr('Menu'), icon: const Icon(Icons.menu), onPressed: () => _scaffold.currentState?.openDrawer()),
              actions: [const _LangSwitch(), _UserMenu(setup: setup, compact: true), const SizedBox(width: 8)],
              shape: Border(bottom: BorderSide(color: CfColors.of(context).line)),
            ),
      body: wide
          ? Row(children: [
              SizedBox(width: 232, child: side),
              Expanded(child: Column(children: [_TopBar(setup: setup, desk: desk), Expanded(child: body)])),
            ])
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
      StaffPage.kiosk => KioskPage(setup: setup, desk: desk, onLock: _lockKiosk),
      StaffPage.wait => WaitlistPage(setup: setup, desk: desk),
      StaffPage.missed => MissedPage(setup: setup, desk: desk),
      StaffPage.services => ClinicPage(setup: setup, desk: desk),
      StaffPage.notif => NotificationsPage(setup: setup, desk: desk),
      StaffPage.users => UsersPage(setup: setup, desk: desk),
      StaffPage.audit => AuditPage(desk: desk),
      StaffPage.reports => ReportsPage(setup: setup, desk: desk),
      StaffPage.settings => SettingsPage(setup: setup, desk: desk),
      StaffPage.setup => WizardBody(setup: setup),
    };
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.setup, required this.desk, required this.pages, required this.current, required this.onGo});
  final ClinicSetup setup;
  final ClinicDesk desk;
  final List<StaffPage> pages;
  final StaffPage current;
  final void Function(StaffPage) onGo;

  /// The small count beside a page: people waiting now, freed times still to fill today.
  int _count(StaffPage p) => switch (p) {
        StaffPage.queue => desk.todayVisits.where((a) => a.status == ApptStatus.waiting || a.status == ApptStatus.checkedIn).length,
        StaffPage.wait => desk.me.runsDay ? desk.freed.where((f) => f.date == desk.today && f.refilledBy == null).length : 0,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = '${setup.clinic['name'] ?? ''}', city = '${setup.clinic['city'] ?? ''}';
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Portal.sideTop, Portal.sideBottom])),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // the clinic's mark and name, as in the clinic's own staff portal
          Container(
            margin: const EdgeInsets.fromLTRB(20, 26, 20, 14),
            padding: const EdgeInsets.only(bottom: 22),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Portal.sideLine))),
            child: Column(children: [
              ClinicLogo(setup.clinic['logo'] as String?, size: 56, fallback: const Icon(Icons.spa_outlined, size: 40, color: Colors.white)),
              const SizedBox(height: 8),
              Text(name, textAlign: TextAlign.center, style: Portal.serif(25, Colors.white)),
              const SizedBox(height: 8),
              Text(tr('Staff portal').toUpperCase(), textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: Portal.sideInk, letterSpacing: 3.4, fontSize: 11, fontWeight: FontWeight.w500)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final p in pages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Semantics(
                    selected: p == current,
                    button: true,
                    child: Material(
                      color: p == current ? Portal.sideOn : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(7),
                        hoverColor: Colors.white.withValues(alpha: .06),
                        onTap: () => onGo(p),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(children: [
                            Icon(p.icon, size: 20, color: p == current ? Colors.white : Portal.sideInk),
                            const SizedBox(width: 13),
                            Expanded(child: Text(tr(p.label), style: t.bodyMedium?.copyWith(color: p == current ? Colors.white : Portal.sideInk, fontWeight: FontWeight.w500))),
                            if (_count(p) > 0)
                              Container(
                                constraints: const BoxConstraints(minWidth: 20),
                                height: 20,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
                                child: Text('${_count(p)}', style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                              ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Portal.sideLine))),
            child: Row(children: [
              const Icon(Icons.location_on_outlined, size: 20, color: Portal.sideInk),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: t.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13), overflow: TextOverflow.ellipsis),
                  Text(city.isEmpty ? tr('single location') : city, style: t.bodySmall?.copyWith(color: Portal.sideMute, fontSize: 11.5), overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The white bar above every page: today's date, language, and who's signed in.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.setup, required this.desk});
  final ClinicSetup setup;
  final ClinicDesk desk;
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    Widget sep() => Container(width: 1, height: 30, color: c.line, margin: const EdgeInsets.symmetric(horizontal: 18));
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: c.line))),
      child: Row(children: [
        const Spacer(),
        ListenableBuilder(listenable: desk, builder: (context, _) => Text(longDay(desk.today, desk.today, lang: lang), style: t.bodyMedium?.copyWith(color: c.fg))),
        sep(),
        const _LangSwitch(),
        sep(),
        _UserMenu(setup: setup),
      ]),
    );
  }
}

/// EN / FR, the staff website's language.
class _LangSwitch extends StatelessWidget {
  const _LangSwitch();
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    return ValueListenableBuilder<String>(
      valueListenable: staffLang,
      builder: (context, code, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (k, label, name) in [('en', 'EN', 'English'), ('fr', 'FR', 'Français')])
          Semantics(
            label: name,
            selected: code == k,
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setStaffLang(k),
              child: Container(
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: code == k ? c.accentSoft : null, borderRadius: BorderRadius.circular(6)),
                child: Text(label, style: t.labelMedium?.copyWith(color: code == k ? Portal.navy : c.muted, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The signed-in person: initials, name and role; opens a menu with Sign out.
class _UserMenu extends StatelessWidget {
  const _UserMenu({required this.setup, this.compact = false});
  final ClinicSetup setup;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final me = setup.me!;
    final name = me.name.isEmpty ? me.email : me.name;
    final initials = name.replaceFirst(RegExp(r'^Dr\.?\s+'), '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    return PopupMenuButton<String>(
      tooltip: tr('Account'),
      position: PopupMenuPosition.under,
      onSelected: (v) {
        if (v == 'out') setup.signOut();
      },
      itemBuilder: (context) => [PopupMenuItem(value: 'out', child: Text(tr('Sign out')))],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 18, backgroundColor: Portal.navy, child: Text(initials, style: t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700))),
          if (!compact) ...[
            const SizedBox(width: 10),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: t.bodyMedium?.copyWith(color: c.fg, fontWeight: FontWeight.w500, height: 1.2)),
              Text(tr(staffRoles[me.role] ?? me.role), style: t.bodySmall?.copyWith(fontSize: 12, height: 1.2)),
            ]),
            const SizedBox(width: 8),
            Icon(Icons.expand_more, size: 18, color: c.muted),
          ],
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
              ? (s.approvalNote.isEmpty
                  ? tr('ClinicFlow didn’t approve {clinic} yet.', {'clinic': s.clinic['name']})
                  : tr('ClinicFlow didn’t approve {clinic} yet: {note}', {'clinic': s.clinic['name'], 'note': s.approvalNote}))
              : tr('ClinicFlow is reviewing {clinic}, usually within one business day. Until it’s approved, patients can’t find or book you online; your team can use the calendar meanwhile.', {'clinic': s.clinic['name']}),
          style: t.bodyMedium?.copyWith(color: fg),
        ),
        if (rejected && admin) ...[
          TextButton(onPressed: widget.onSetup, child: Text(tr('Update details'))),
          FilledButton(
            style: smallFilled,
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await act(context, s.resubmit, done: tr('Sent back to ClinicFlow for review'));
                    if (mounted) setState(() => _busy = false);
                  },
            child: Text(tr('Resubmit')),
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
