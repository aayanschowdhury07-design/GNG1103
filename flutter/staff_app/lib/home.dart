import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'account.dart';
import 'alerts.dart';
import 'l10n.dart';
import 'queue.dart';
import 'schedule.dart';
import 'ui.dart';
import 'waitlist.dart';

enum StaffTab { queue, schedule, waitlist, alerts, me }

/// The tabs each role sees (as in the prototype). The security rules enforce the same limits.
List<StaffTab> tabsFor(StaffMember me, Map<String, dynamic> clinic) {
  final waitlistOn = (clinic['features'] as Map?)?['waitlist'] != false;
  return switch (me.role) {
    'admin' || 'frontdesk' => [StaffTab.queue, StaffTab.schedule, if (waitlistOn) StaffTab.waitlist, StaffTab.alerts, StaffTab.me],
    'clinician' => [StaffTab.queue, StaffTab.schedule, StaffTab.alerts, StaffTab.me],
    _ => [StaffTab.queue, StaffTab.alerts, StaffTab.me],
  };
}

/// The staff app once signed in: the clinic at the top, the day's tabs at the bottom.
class StaffHome extends StatefulWidget {
  const StaffHome({super.key, required this.setup});
  final ClinicSetup setup;
  @override
  State<StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<StaffHome> {
  StaffTab _tab = StaffTab.queue;

  @override
  Widget build(BuildContext context) {
    final setup = widget.setup, desk = setup.desk!, c = CfColors.of(context), t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([setup, desk, staffLang]),
      builder: (context, _) {
        final tabs = tabsFor(desk.me, setup.clinic);
        final tab = tabs.contains(_tab) ? _tab : tabs.first;
        final alerts = AlertsTab.count(desk);
        final body = switch (tab) {
          StaffTab.queue => QueueTab(setup: setup, desk: desk),
          StaffTab.schedule => ScheduleTab(setup: setup, desk: desk),
          StaffTab.waitlist => WaitlistTab(setup: setup, desk: desk),
          StaffTab.alerts => AlertsTab(setup: setup, desk: desk, onWaitlist: () => setState(() => _tab = StaffTab.waitlist)),
          StaffTab.me => AccountTab(setup: setup, desk: desk),
        };
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: Row(children: [
              ClinicMark(setup, size: 32),
              const SizedBox(width: 10),
              Expanded(child: Text('${setup.clinic['name'] ?? ''}', style: t.titleMedium, overflow: TextOverflow.ellipsis)),
            ]),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: c.accentSoft,
                  child: Text(initialsOf(desk.me.name.isEmpty ? desk.me.email : desk.me.name), style: t.labelMedium?.copyWith(color: c.accent, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
            shape: Border(bottom: BorderSide(color: c.line)),
          ),
          body: Column(children: [
            if (desk.error != null)
              Container(
                width: double.infinity,
                color: c.critSoft,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(tr('Some clinic data couldn’t load. Pull down or reopen the app.'), style: t.bodySmall?.copyWith(color: c.crit)),
              ),
            Expanded(child: KeyedSubtree(key: ValueKey(tab), child: body)),
          ]),
          floatingActionButton: tab == StaffTab.queue && desk.me.runsDay
              ? FloatingActionButton.extended(onPressed: () => addWalkIn(context, setup, desk), icon: const Icon(Icons.person_add_alt_1_outlined), label: Text(tr('Add walk-in')))
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: tabs.indexOf(tab),
            onDestinationSelected: (i) => setState(() => _tab = tabs[i]),
            destinations: [
              for (final x in tabs)
                switch (x) {
                  StaffTab.queue => NavigationDestination(icon: const Icon(Icons.groups_outlined), selectedIcon: const Icon(Icons.groups), label: tr('Who’s here')),
                  StaffTab.schedule => NavigationDestination(icon: const Icon(Icons.calendar_today_outlined), selectedIcon: const Icon(Icons.calendar_today), label: tr('Schedule')),
                  StaffTab.waitlist => NavigationDestination(icon: const Icon(Icons.playlist_add_check), label: tr('Waitlist')),
                  StaffTab.alerts => NavigationDestination(
                      icon: Badge(isLabelVisible: alerts > 0, label: Text('$alerts'), child: const Icon(Icons.notifications_none)),
                      selectedIcon: Badge(isLabelVisible: alerts > 0, label: Text('$alerts'), child: const Icon(Icons.notifications)),
                      label: tr('Alerts'),
                    ),
                  StaffTab.me => NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: tr('Account')),
                },
            ],
          ),
        );
      },
    );
  }
}
