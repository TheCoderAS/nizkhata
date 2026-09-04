// App theme — mirrors the web app's brand: indigo primary, emerald accent,
// soft elevated surfaces, Material 3, light + dark.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const brand = Color(0xFF4F46E5); // indigo-600 (grad-from)
  static const brandTo = Color(0xFF7C3AED); // violet (grad-to)
  static const accent2 = Color(0xFF10B981); // emerald (positive / receivable)
  static const danger = Color(0xFFEF4444); // red (negative / payable)
  static const warning = Color(0xFFF59E0B); // amber (approaching a limit / due soon)
}

/// Consistent spacing scale (4pt grid) used across screens.
class Gap {
  static const xs = SizedBox(height: 4, width: 4);
  static const sm = SizedBox(height: 8, width: 8);
  static const md = SizedBox(height: 12, width: 12);
  static const lg = SizedBox(height: 16, width: 16);
  static const xl = SizedBox(height: 24, width: 24);
}

ThemeData _base(Brightness brightness, ColorScheme scheme) {
  final base = ThemeData(brightness: brightness);
  // Weights kept deliberately restrained — one clear emphasis level (titles),
  // everything else regular/medium — so the UI reads calm and modern rather
  // than shouty. Only headline/title carry weight; body & menu text stay normal.
  final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
    headlineSmall: GoogleFonts.inter(fontWeight: FontWeight.w700, letterSpacing: -0.4),
    titleLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, letterSpacing: -0.2),
    titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w500),
    titleSmall: GoogleFonts.inter(fontWeight: FontWeight.w500),
    labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w500),
  );
  final radius = BorderRadius.circular(14);
  // Dark: a dim base so elevated cards read clearly above it. Light: plain surface.
  final scaffoldBg = brightness == Brightness.dark ? scheme.surfaceDim : scheme.surface;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffoldBg,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 2,
      backgroundColor: scaffoldBg,
      surfaceTintColor: scheme.surfaceTint,
      // Explicit foreground so the title/icons stay legible in light mode
      // (without this the title rendered near-invisible on the light surface).
      foregroundColor: scheme.onSurface,
      iconTheme: IconThemeData(color: scheme.onSurface),
      toolbarHeight: 64,
      titleTextStyle: textTheme.titleLarge
          ?.copyWith(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      // Cards sit a step ABOVE the scaffold surface so they lift off the
      // background (using the darkest container made them read sunken/grey in
      // dark mode). A hairline border + soft shadow give quiet depth.
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: brightness == Brightness.dark ? 0.4 : 0.10),
      surfaceTintColor: Colors.transparent,
      color: brightness == Brightness.dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      elevation: 3,
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => textTheme.labelMedium?.copyWith(
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radius)),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHighest,
      labelStyle: textTheme.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: scheme.surfaceContainerLow,
      showDragHandle: true,
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.7), thickness: 1),
  );
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: Brightness.light,
  ).copyWith(secondary: AppColors.accent2);
  return _base(Brightness.light, scheme);
}

ThemeData buildDarkTheme() {
  // Near-black canvas. The seeded dark ramp is a blue-grey that washes out on
  // OLED and leaves cards barely distinguishable from the background; dropping
  // the floor (and keeping the containers cool but lifted) makes cards, sheets
  // and the nav pill read as planes above the canvas instead of more grey.
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: Brightness.dark,
  ).copyWith(
    secondary: AppColors.accent2,
    surface: const Color(0xFF0B0D11),
    surfaceDim: const Color(0xFF07080B), // the canvas itself
    surfaceContainerLowest: const Color(0xFF0D0F14),
    surfaceContainerLow: const Color(0xFF121419),
    surfaceContainer: const Color(0xFF16191F), // nav pill
    surfaceContainerHigh: const Color(0xFF1B1F26), // cards
    surfaceContainerHighest: const Color(0xFF222730),
    outlineVariant: const Color(0xFF2A2F39),
  );
  return _base(Brightness.dark, scheme);
}

const brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.brand, AppColors.brandTo],
);
