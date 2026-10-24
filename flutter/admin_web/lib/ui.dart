import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

/// A staff website page: eyebrow, title and actions, then its content, scrolling as one.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, this.eyebrow, required this.title, this.actions = const [], required this.children});
  final String? eyebrow;
  final String title;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(28, 24, 28, 40), children: [
      Wrap(spacing: 16, runSpacing: 12, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (eyebrow != null) Text(eyebrow!, style: t.bodySmall),
          Semantics(header: true, child: Text(title, style: t.headlineMedium)),
        ]),
        if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
      ]),
      const SizedBox(height: 20),
      for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 16), child: c),
    ]);
  }
}

/// A white card with an optional title row.
class Panel extends StatelessWidget {
  const Panel({super.key, this.title, this.trailing, this.note, required this.child, this.padding = const EdgeInsets.all(20)});
  final String? title, note;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null || trailing != null) ...[
          Row(children: [
            if (title != null) Expanded(child: Semantics(header: true, child: Text(title!, style: t.titleMedium))),
            ?trailing,
          ]),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(note!, style: t.bodySmall)),
          const SizedBox(height: 12),
        ],
        child,
      ]),
    );
  }
}

/// Two panels side by side on wide screens, stacked on narrow ones.
class Columns extends StatelessWidget {
  const Columns({super.key, required this.children, this.flex});
  final List<Widget> children;
  final List<int>? flex;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 860) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 16), child: children[i]),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(flex: flex?[i] ?? 1, child: children[i]),
          ],
        ]);
      });
}

enum Tone { good, warn, crit, info, mute }

/// A key figure: label, number, and a line of context.
class Kpi extends StatelessWidget {
  const Kpi({super.key, required this.label, required this.value, this.sub, this.tone});
  final String label, value;
  final String? sub;
  final Tone? tone;
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 190),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: t.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: t.headlineSmall?.copyWith(fontFamily: t.bodyMedium?.fontFamily, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
        if (sub != null) Text(sub!, style: t.bodySmall?.copyWith(color: toneColor(c, tone))),
      ]),
    );
  }
}

class KpiRow extends StatelessWidget {
  const KpiRow({super.key, required this.children});
  final List<Kpi> children;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 12, runSpacing: 12, children: children);
}

Color toneColor(CfColors c, Tone? tone) => switch (tone) {
      Tone.good => c.good,
      Tone.warn => c.warn,
      Tone.crit => c.crit,
      Tone.info => c.accent,
      _ => c.muted,
    };

Color toneSoft(CfColors c, Tone tone) => switch (tone) {
      Tone.good => c.goodSoft,
      Tone.warn => c.warnSoft,
      Tone.crit => c.critSoft,
      Tone.info => c.accentSoft,
      Tone.mute => c.surface2,
    };

/// A short label on a soft background: "Priority", "Forms open", "Refilled".
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.tone = Tone.mute});
  final String label;
  final Tone tone;
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context);
    // sized to its label, even in a table cell that hands it the column's full width
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: toneSoft(c, tone), borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: tone == Tone.mute ? c.muted : toneColor(c, tone))),
      ),
    );
  }
}

/// A horizontal bar: label, filled share, figure. Under half full shows in the warning colour.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.label, required this.share, required this.figure, this.flagLow = true});
  final String label, figure;
  final double share;

  /// Utilization under half is worth a look; plain counts aren't.
  final bool flagLow;
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 150, child: Text(label, style: t.bodyMedium, overflow: TextOverflow.ellipsis)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: share.clamp(0, 1), minHeight: 10, backgroundColor: c.surface2, color: flagLow && share < .5 ? c.warn : c.accent),
          ),
        ),
        SizedBox(width: 72, child: Text(figure, textAlign: TextAlign.right, style: t.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
      ]),
    );
  }
}

/// A plain table: a header row and rows of cells, scrolling sideways on narrow screens.
class SimpleTable extends StatelessWidget {
  const SimpleTable({super.key, required this.columns, required this.rows, this.empty = 'Nothing here.', this.widths});
  final List<String> columns;
  final List<List<Widget>> rows;
  final String empty;
  final Map<int, TableColumnWidth>? widths;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    if (rows.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(empty, style: t.bodySmall));
    Widget cell(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), child: w);
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: box.maxWidth),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            columnWidths: widths,
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.lineStrong))),
                children: [for (final h in columns) cell(Text(h, style: t.labelMedium?.copyWith(color: c.muted)))],
              ),
              for (final r in rows) TableRow(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))), children: [for (final w in r) cell(w)]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small buttons in a table row.
class RowActions extends StatelessWidget {
  const RowActions(this.children, {super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: children);
}

ButtonStyle get smallButton => OutlinedButton.styleFrom(minimumSize: const Size(40, 36), padding: const EdgeInsets.symmetric(horizontal: 12), visualDensity: VisualDensity.compact);
ButtonStyle get smallFilled => FilledButton.styleFrom(minimumSize: const Size(40, 36), padding: const EdgeInsets.symmetric(horizontal: 12), visualDensity: VisualDensity.compact);

Widget small(String label, VoidCallback? onPressed, {bool primary = false, bool danger = false}) {
  if (primary) return FilledButton(style: smallFilled, onPressed: onPressed, child: Text(label));
  return Builder(
    builder: (context) => OutlinedButton(
      style: smallButton.copyWith(foregroundColor: danger ? WidgetStatePropertyAll(CfColors.of(context).crit) : null),
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}

/// A one-line message at the bottom of the screen, with Undo when the change can be reversed.
void say(BuildContext context, String text, {VoidCallback? undo}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: undo == null ? null : SnackBarAction(label: 'Undo', onPressed: undo)));
}

/// Runs a change and reports a refused write in plain words instead of failing silently.
Future<void> act(BuildContext context, Future<void> Function() change, {String? done, VoidCallback? undo}) async {
  try {
    await change();
    if (done != null && context.mounted) say(context, done, undo: undo);
  } catch (e) {
    if (context.mounted) say(context, 'Couldn’t save that: ${'$e'.contains('permission') ? 'your role can’t make this change' : e}');
  }
}

String pct(num part, num whole) => whole == 0 ? '—' : '${(part / whole * 100).round()}%';
