import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'models.dart';

/// The prototype's design tokens (tokens.css), converted from OKLCH to sRGB.
/// Paper: warm off-white. Ink: blue-black. One accent: calm clinical blue.
@immutable
class CfColors extends ThemeExtension<CfColors> {
  const CfColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.lineStrong,
    required this.fg,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.accentFg,
    required this.good,
    required this.goodSoft,
    required this.warn,
    required this.warnSoft,
    required this.crit,
    required this.critSoft,
    required this.hero,
    required this.heroFg,
    required this.stBooked,
    required this.stConfirmed,
    required this.stArrived,
    required this.stWaiting,
    required this.stInVisit,
    required this.stDone,
  });

  /// [line] separates content; [lineStrong] outlines controls (at least 3:1 contrast).
  final Color bg, surface, surface2, line, lineStrong, fg, muted, accent, accentSoft, accentFg;
  final Color good, goodSoft, warn, warnSoft, crit, critSoft, hero, heroFg;

  /// One hue per visit status (see [statusColor]).
  final Color stBooked, stConfirmed, stArrived, stWaiting, stInVisit, stDone;

  static const light = CfColors(
    bg: Color(0xFFFAFAF8), surface: Color(0xFFFFFFFF), surface2: Color(0xFFF3F4F2),
    line: Color(0xFFE5E6E2), lineStrong: Color(0xFF888C94), fg: Color(0xFF1C2128), muted: Color(0xFF5E6570),
    accent: Color(0xFF3C649F), accentSoft: Color(0xFFEDF2F9), accentFg: Color(0xFFFFFFFF),
    good: Color(0xFF1F7A53), goodSoft: Color(0xFFE7F4ED), warn: Color(0xFF94590A), warnSoft: Color(0xFFFBF1DF),
    crit: Color(0xFFB3261D), critSoft: Color(0xFFFBECEB), hero: Color(0xFF2C4C7C), heroFg: Color(0xFFFFFFFF),
    stBooked: Color(0xFF5E6570), stConfirmed: Color(0xFF3C649F), stArrived: Color(0xFF0A6C71),
    stWaiting: Color(0xFF94590A), stInVisit: Color(0xFF704899), stDone: Color(0xFF54585F),
  );

  static const dark = CfColors(
    bg: Color(0xFF121417), surface: Color(0xFF1A1D22), surface2: Color(0xFF22262C),
    line: Color(0xFF2E333A), lineStrong: Color(0xFF6F757D), fg: Color(0xFFE8EAED), muted: Color(0xFF9BA2AD),
    accent: Color(0xFF8FB0E3), accentSoft: Color(0xFF1F2B3D), accentFg: Color(0xFF101722),
    good: Color(0xFF71C79C), goodSoft: Color(0xFF16302A), warn: Color(0xFFE2B064), warnSoft: Color(0xFF342814),
    crit: Color(0xFFF0A096), critSoft: Color(0xFF3A1F1D), hero: Color(0xFF24395A), heroFg: Color(0xFFEEF2F8),
    stBooked: Color(0xFF9BA2AD), stConfirmed: Color(0xFF8FB0E3), stArrived: Color(0xFF6AC2C6),
    stWaiting: Color(0xFFE2B064), stInVisit: Color(0xFFC0A1E4), stDone: Color(0xFF8E939A),
  );

  Color statusColor(ApptStatus s) => switch (s) {
        ApptStatus.booked || ApptStatus.cancelled => stBooked,
        ApptStatus.confirmed => stConfirmed,
        ApptStatus.checkedIn => stArrived,
        ApptStatus.waiting => stWaiting,
        ApptStatus.inVisit => stInVisit,
        ApptStatus.complete => stDone,
        ApptStatus.late || ApptStatus.noShow => crit,
      };

  static CfColors of(BuildContext context) => Theme.of(context).extension<CfColors>()!;

  @override
  CfColors copyWith() => this;

  @override
  CfColors lerp(ThemeExtension<CfColors>? other, double t) => t < .5 ? this : (other as CfColors? ?? this);
}

/// Light is the default; dark mirrors the prototype's dark tokens.
ThemeData clinicFlowTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? CfColors.dark : CfColors.light;
  // only the font families come from google_fonts: its TextTheme helpers target the
  // standalone material_ui package, which doesn't mix with flutter/material types
  final base = ThemeData(brightness: brightness, useMaterial3: true, fontFamily: GoogleFonts.inter().fontFamily);
  final body = base.textTheme.apply(bodyColor: c.fg, displayColor: c.fg);
  // Source Serif 4 for screen titles and the brand only; every label and figure is Inter
  TextStyle serif(double size) => GoogleFonts.sourceSerif4(fontSize: size, fontWeight: FontWeight.w500, color: c.fg, letterSpacing: -.2);
  final text = body.copyWith(
    headlineMedium: serif(28),
    headlineSmall: serif(23),
    titleLarge: body.titleLarge?.copyWith(fontSize: 19, fontWeight: FontWeight.w600),
    titleMedium: body.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
    bodyMedium: body.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
    bodySmall: body.bodySmall?.copyWith(fontSize: 13, height: 1.45, color: c.muted),
    labelLarge: body.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
    labelMedium: body.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
  );
  final scheme = ColorScheme.fromSeed(seedColor: c.accent, brightness: brightness).copyWith(
    primary: c.accent,
    onPrimary: c.accentFg,
    surface: c.bg,
    onSurface: c.fg,
    onSurfaceVariant: c.muted,
    outline: c.lineStrong,
    outlineVariant: c.line,
    error: c.crit,
    secondaryContainer: c.accentSoft,
  );
  const tall = Size(64, 48); // touch targets: 48 dp, above the 44 px floor
  final radius = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    textTheme: text,
    extensions: [c],
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(backgroundColor: c.bg, foregroundColor: c.fg, elevation: 0, scrolledUnderElevation: 0, titleTextStyle: text.headlineSmall),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: tall, shape: radius, textStyle: text.labelLarge)),
    // secondary actions are text links in the accent colour, as in the prototype
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: c.accent, shape: radius, textStyle: text.labelLarge)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: tall, shape: radius, side: BorderSide(color: c.lineStrong), foregroundColor: c.fg)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.lineStrong)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.lineStrong)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.accent, width: 2)),
      labelStyle: TextStyle(color: c.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    checkboxTheme: CheckboxThemeData(side: BorderSide(color: c.lineStrong, width: 1.5)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.bg,
      indicatorColor: c.accentSoft,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      height: 68,
    ),
    snackBarTheme: SnackBarThemeData(backgroundColor: c.fg, contentTextStyle: text.bodyMedium?.copyWith(color: c.bg), actionTextColor: c.bg, behavior: SnackBarBehavior.floating),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.bg, showDragHandle: true),
  );
}

/// A visit status: coloured text with a dot. Outlined dot = not here yet, filled = arrived.
class StatusMark extends StatelessWidget {
  const StatusMark(this.status, {super.key});
  final ApptStatus status;

  @override
  Widget build(BuildContext context) {
    final color = CfColors.of(context).statusColor(status);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: status.arrived ? color : null,
          border: status.arrived ? null : Border.all(color: color, width: 1.5),
        ),
      ),
      const SizedBox(width: 6),
      Text(status.label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
    ]);
  }
}
