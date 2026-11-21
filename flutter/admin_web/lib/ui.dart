import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'portal_theme.dart';

/// A staff website page: title and actions, a line of context under the title, then its
/// content as sections on one white page, scrolling as one.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, this.eyebrow, required this.title, this.actions = const [], required this.children});
  final String? eyebrow;
  final String title;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(32, 30, 32, 48), children: [
      Wrap(spacing: 16, runSpacing: 12, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Semantics(header: true, child: Text(title, style: t.headlineMedium)),
          if (eyebrow != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(eyebrow!, style: t.bodyLarge)),
        ]),
        if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
      ]),
      const SizedBox(height: 28),
      for (var i = 0; i < children.length; i++) Padding(padding: EdgeInsets.only(bottom: i == children.length - 1 ? 0 : 36), child: children[i]),
    ]);
  }
}

/// A section of the page: a title row with a thin rule under it, then the content.
/// No box around it; [boxed] keeps an outline for things like the calendar grid.
class Panel extends StatelessWidget {
  const Panel({super.key, this.title, this.trailing, this.note, required this.child, this.padding = EdgeInsets.zero, this.boxed = false});
  final String? title, note;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null || trailing != null) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Row(children: [
                if (title != null) Flexible(child: Semantics(header: true, child: Text(title!, style: t.titleMedium))),
                if (note != null && note!.length <= 48) ...[const SizedBox(width: 10), Flexible(child: Text(note!, style: t.bodySmall))],
              ]),
            ),
            ?trailing,
          ]),
        ),
        if (note != null && note!.length > 48) Padding(padding: const EdgeInsets.only(top: 0, bottom: 12), child: Text(note!, style: t.bodySmall)),
        Divider(height: 1, color: c.line),
        const SizedBox(height: 4),
      ],
      Padding(padding: boxed ? padding : EdgeInsets.zero, child: child),
    ]);
    if (!boxed) return content;
    return Container(decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(8)), child: content);
  }
}

/// Sections side by side on wide screens, with one thin vertical line between them;
/// stacked on narrow ones.
class Columns extends StatelessWidget {
  const Columns({super.key, required this.children, this.flex, this.stackBelow = 860});
  final List<Widget> children;
  final List<int>? flex;

  /// Narrower than this, the sections stack.
  final double stackBelow;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < stackBelow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 36), child: children[i]),
          ]);
        }
        final line = CfColors.of(context).line;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < children.length; i++)
            Expanded(
              flex: flex?[i] ?? 1,
              child: Container(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 28, right: i == children.length - 1 ? 0 : 28),
                decoration: i == 0 ? null : BoxDecoration(border: Border(left: BorderSide(color: line))),
                child: children[i],
              ),
            ),
        ]);
      });
}

enum Tone { good, warn, crit, info, mute }

/// A key figure: label (with an optional icon), number, and a line of context or a small extra.
class Kpi extends StatelessWidget {
  const Kpi({super.key, required this.label, required this.value, this.sub, this.tone, this.icon, this.extra});
  final String label, value;
  final String? sub;
  final Tone? tone;
  final IconData? icon;
  final Widget? extra;
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        if (icon != null) ...[Icon(icon, size: 22, color: Portal.navy), const SizedBox(width: 10)],
        Flexible(child: Text(label, style: t.bodyMedium?.copyWith(color: c.fg, height: 1.3), maxLines: 2)),
      ]),
      const SizedBox(height: 10),
      Text(value, style: t.headlineMedium?.copyWith(fontSize: 30, fontWeight: FontWeight.w500, letterSpacing: -.4, fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(height: 8),
      if (sub != null) Text(sub!, style: t.bodySmall?.copyWith(color: toneColor(c, tone))),
      ?extra,
    ]);
  }
}

/// Key figures in one strip: a line above and below, thin dividers between them.
class KpiRow extends StatelessWidget {
  const KpiRow({super.key, required this.children});
  final List<Kpi> children;
  @override
  Widget build(BuildContext context) {
    final line = CfColors.of(context).line;
    return LayoutBuilder(builder: (context, box) {
      // as many as fit (at least 128 px each), spread evenly over the rows
      final fit = (box.maxWidth / 128).floor().clamp(1, children.length);
      final nRows = (children.length / fit).ceil();
      final per = (children.length / nRows).ceil();
      final rows = <List<Kpi>>[for (var i = 0; i < children.length; i += per) children.sublist(i, (i + per).clamp(0, children.length))];
      return Container(
        decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: line))),
        child: Column(children: [
          for (var r = 0; r < rows.length; r++)
            Container(
              decoration: r == 0 ? null : BoxDecoration(border: Border(top: BorderSide(color: line))),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < per; i++)
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.fromLTRB(i == 0 ? 0 : 20, 20, 16, 20),
                        decoration: i == 0 ? null : BoxDecoration(border: Border(left: BorderSide(color: line))),
                        child: i < rows[r].length ? rows[r][i] : const SizedBox(),
                      ),
                    ),
                ]),
              ),
            ),
        ]),
      );
    });
  }
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

/// A short label on a soft background, with a dot: "Priority", "Forms open", "Refilled".
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.tone = Tone.mute});
  final String label;
  final Tone tone;
  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context);
    final fg = tone == Tone.mute ? c.muted : toneColor(c, tone);
    // sized to its label, even in a table cell that hands it the column's full width
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: toneSoft(c, tone), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Flexible(child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg))),
        ]),
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
  const SimpleTable({super.key, required this.columns, required this.rows, this.empty, this.widths});
  final List<String> columns;
  final List<List<Widget>> rows;
  final String? empty;
  final Map<int, TableColumnWidth>? widths;

  @override
  Widget build(BuildContext context) {
    final c = CfColors.of(context), t = Theme.of(context).textTheme;
    if (rows.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(empty ?? tr('Nothing here.'), style: t.bodySmall));
    Widget cell(Widget w, int i, {bool head = false}) => Padding(padding: EdgeInsets.fromLTRB(i == 0 ? 0 : 10, head ? 12 : 13, 10, head ? 12 : 13), child: w);
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
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                children: [for (var i = 0; i < columns.length; i++) cell(Text(columns[i].toUpperCase(), style: t.labelMedium?.copyWith(color: c.muted, fontSize: 11.5, letterSpacing: .7)), i, head: true)],
              ),
              for (final r in rows) TableRow(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))), children: [for (var i = 0; i < r.length; i++) cell(r[i], i)]),
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
    ..showSnackBar(SnackBar(content: Text(text), action: undo == null ? null : SnackBarAction(label: tr('Undo'), onPressed: undo)));
}

/// Runs a change and reports a refused write in plain words instead of failing silently.
Future<void> act(BuildContext context, Future<void> Function() change, {String? done, VoidCallback? undo}) async {
  try {
    await change();
    if (done != null && context.mounted) say(context, done, undo: undo);
  } catch (e) {
    if (context.mounted) say(context, tr('Couldn’t save that: {why}', {'why': '$e'.contains('permission') ? tr('your role can’t make this change') : e}));
  }
}

String pct(num part, num whole) => whole == 0 ? '—' : '${(part / whole * 100).round()}%';
