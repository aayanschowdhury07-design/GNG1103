import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The staff portal look (design-mockups/staff-portal): a navy sidebar, one white page with
/// sections divided by thin lines instead of boxes, Inter everywhere, and a serif only for
/// the clinic's name in the sidebar. The patient app keeps the shared clinicFlowTheme.
class Portal {
  static const side = Color(0xFF1F3A5C), sideTop = Color(0xFF213E62), sideBottom = Color(0xFF1C3555);
  static const sideOn = Color(0xFF2C4A72), sideInk = Color(0xFFD6DFEB), sideMute = Color(0xFF9FB1C9), sideLine = Color(0x1FFFFFFF);
  static const navy = Color(0xFF1F3A5C), link = Color(0xFF2F5A96);
  static TextStyle serif(double size, Color color) => GoogleFonts.lora(fontSize: size, height: 1.1, color: color, letterSpacing: -.2);
}

const portalColors = CfColors(
  bg: Color(0xFFFFFFFF), surface: Color(0xFFFFFFFF), surface2: Color(0xFFF3F5F8),
  line: Color(0xFFE3E7ED), lineStrong: Color(0xFF8A94A6), fg: Color(0xFF1B2A44), muted: Color(0xFF6A768A),
  accent: Portal.link, accentSoft: Color(0xFFE9EFF7), accentFg: Color(0xFFFFFFFF),
  good: Color(0xFF2A7A52), goodSoft: Color(0xFFE7F3EC), warn: Color(0xFFA2620F), warnSoft: Color(0xFFFBF0DD),
  crit: Color(0xFFB3362B), critSoft: Color(0xFFFAE8E5), hero: Portal.navy, heroFg: Color(0xFFFFFFFF),
  stBooked: Color(0xFF6A768A), stConfirmed: Color(0xFF2F5A96), stArrived: Color(0xFF0A6C71),
  stWaiting: Color(0xFFA2620F), stInVisit: Color(0xFF704899), stDone: Color(0xFF54585F),
);

ThemeData staffPortalTheme() {
  const c = portalColors;
  final base = ThemeData(brightness: Brightness.light, useMaterial3: true, fontFamily: GoogleFonts.inter().fontFamily);
  final body = base.textTheme.apply(bodyColor: c.fg, displayColor: c.fg);
  final text = body.copyWith(
    headlineMedium: body.headlineMedium?.copyWith(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -.6, height: 1.15),
    headlineSmall: body.headlineSmall?.copyWith(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -.3),
    titleLarge: body.titleLarge?.copyWith(fontSize: 19, fontWeight: FontWeight.w600),
    titleMedium: body.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -.2),
    bodyLarge: body.bodyLarge?.copyWith(fontSize: 16, color: c.muted),
    bodyMedium: body.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
    bodySmall: body.bodySmall?.copyWith(fontSize: 13, height: 1.45, color: c.muted),
    labelLarge: body.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium: body.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
  );
  final scheme = ColorScheme.fromSeed(seedColor: Portal.navy, brightness: Brightness.light).copyWith(
    primary: Portal.navy,
    onPrimary: Colors.white,
    surface: c.bg,
    onSurface: c.fg,
    onSurfaceVariant: c.muted,
    outline: c.lineStrong,
    outlineVariant: c.line,
    error: c.crit,
    secondaryContainer: c.accentSoft,
  );
  const tall = Size(64, 44);
  final radius = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    textTheme: text,
    extensions: const [c],
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(backgroundColor: c.bg, foregroundColor: c.fg, elevation: 0, scrolledUnderElevation: 0, titleTextStyle: text.titleMedium),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: tall, backgroundColor: Portal.navy, foregroundColor: Colors.white, shape: radius, textStyle: text.labelLarge)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 44), foregroundColor: Portal.link, shape: radius, textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: tall, shape: radius, side: BorderSide(color: c.line, width: 1.2), foregroundColor: c.fg, backgroundColor: Colors.white, textStyle: text.labelLarge)),
    segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(side: WidgetStatePropertyAll(BorderSide(color: c.line)))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.lineStrong)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.lineStrong)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Portal.link, width: 2)),
      labelStyle: TextStyle(color: c.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    checkboxTheme: CheckboxThemeData(side: BorderSide(color: c.lineStrong, width: 1.5)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : c.lineStrong),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Portal.navy : c.surface2),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Portal.navy : c.line),
    ),
    dialogTheme: DialogThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    popupMenuTheme: PopupMenuThemeData(color: Colors.white, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: c.line))),
    snackBarTheme: SnackBarThemeData(backgroundColor: c.fg, contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white), actionTextColor: Colors.white, behavior: SnackBarBehavior.floating),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.bg, showDragHandle: true),
    drawerTheme: const DrawerThemeData(backgroundColor: Portal.side),
  );
}
