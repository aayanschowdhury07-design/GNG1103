import 'dart:async';

import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:clinicflow_firebase/clinicflow_firebase.dart';
import 'package:flutter/material.dart';

import 'steps.dart';

/// The setup wizard for a new clinic, full screen. Once setup is finished it lives on as a
/// page of the staff website (see [WizardBody]).
class WizardScreen extends StatelessWidget {
  const WizardScreen({super.key, required this.setup});
  final ClinicSetup setup;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(8)),
            child: Text(setup.clinic['initials'] ?? '', style: t.labelMedium?.copyWith(color: c.heroFg)),
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(setup.clinic['name'] ?? '', overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          SetupTimer(setup: setup),
          const SizedBox(width: 16),
          if (wide) Text(setup.user?.email ?? '', style: t.bodySmall),
          TextButton(onPressed: setup.signOut, child: const Text('Sign out')),
          const SizedBox(width: 12),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: c.line)),
      ),
      body: WizardBody(setup: setup, showTimer: false),
    );
  }
}

/// Eight steps on the left, the current one on the right. Every step saves as it goes, so an
/// admin can leave and come back; the timer checks the "under an hour" goal.
class WizardBody extends StatelessWidget {
  const WizardBody({super.key, required this.setup, this.showTimer = true});
  final ClinicSetup setup;
  final bool showTimer;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListenableBuilder(
      listenable: setup,
      builder: (context, _) {
        final body = SetupStep(setup: setup, step: setup.step);
        return Column(children: [
          if (setup.finished || showTimer)
            Container(
              width: double.infinity,
              color: setup.finished ? c.goodSoft : c.surface2,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(children: [
                Expanded(
                  child: Text(
                    setup.finished
                        ? '${setup.clinic['name']} is set up${setup.approved ? (setup.clinic['listed'] == true ? ' and listed for patients' : '') : ' and waiting for ClinicFlow’s review'}. Every step can still be changed.'
                        : 'Setup isn’t finished yet. Patients can book once it is.',
                    style: t.bodyMedium?.copyWith(color: setup.finished ? c.good : c.fg, fontWeight: FontWeight.w500),
                  ),
                ),
                if (showTimer) ...[const SizedBox(width: 16), SetupTimer(setup: setup)],
              ]),
            ),
          Expanded(
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 280, child: _StepList(setup: setup)),
                    Container(width: 1, color: c.line),
                    Expanded(child: body),
                  ])
                : Column(children: [_StepStrip(setup: setup), Expanded(child: body)]),
          ),
        ]);
      },
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.setup});
  final ClinicSetup setup;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 20), children: [
      Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), child: Text('Setup', style: t.titleMedium)),
      for (var i = 0; i < setupSteps.length; i++)
        Builder(builder: (context) {
          final n = i + 1, done = setup.doneSteps.contains(n), now = setup.step == n;
          return Semantics(
            button: true,
            selected: now,
            label: 'Step $n, ${setupSteps[i]}${done ? ', done' : ''}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setup.goToStep(n),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(color: now ? c.surface2 : null, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? c.good : null,
                      border: Border.all(color: done ? c.good : now ? c.accent : c.lineStrong, width: 1.5),
                    ),
                    child: done ? Icon(Icons.check, size: 14, color: c.bg) : Text('$n', style: t.labelMedium?.copyWith(color: now ? c.accent : c.muted)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(setupSteps[i], style: t.bodyMedium?.copyWith(color: now ? c.fg : done ? c.fg : c.muted, fontWeight: now ? FontWeight.w600 : null))),
                ]),
              ),
            ),
          );
        }),
    ]);
  }
}

/// On narrow screens the steps become a horizontal strip.
class _StepStrip extends StatelessWidget {
  const _StepStrip({required this.setup});
  final ClinicSetup setup;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
          for (var i = 0; i < setupSteps.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${i + 1}. ${setupSteps[i]}'),
                selected: setup.step == i + 1,
                avatar: setup.doneSteps.contains(i + 1) ? const Icon(Icons.check, size: 16) : null,
                onSelected: (_) => setup.goToStep(i + 1),
              ),
            ),
        ]),
      );
}

/// "Setup time 12:04", ticking; "Finished in 38:12 (target under 60 min)" once done.
class SetupTimer extends StatefulWidget {
  const SetupTimer({super.key, required this.setup});
  final ClinicSetup setup;
  @override
  State<SetupTimer> createState() => _SetupTimerState();
}

class _SetupTimerState extends State<SetupTimer> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.setup, start = s.startedAt;
    if (start == null) return const SizedBox.shrink();
    final d = (s.finishedAt ?? DateTime.now()).difference(start);
    final mmss = '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    final c = CfColors.of(context), onTarget = d.inMinutes < 60;
    return Text(
      s.finished ? 'Finished in $mmss · target under 60 min' : 'Setup time $mmss',
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: s.finished ? (onTarget ? c.good : c.warn) : c.muted, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}
