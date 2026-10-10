import 'package:flutter/material.dart';

/// Design tokens. Widgets read colours / radii / spacing from here — never
/// hardcode them (same rule as tio-help).
class StudioColors {
  static const neon = Color(0xFFFF4F8B); // 霓虹 pink
  static const amber = Color(0xFFFFB627); // 小巴 amber
  static const teal = Color(0xFF2EC4B6);
  static const error = Color(0xFFE53935);
  static const background = Color(0xFF14121A);
  static const surface = Color(0xFF1F1C27);
  static const surfaceHigh = Color(0xFF2A2634);
  static const textPrimary = Color(0xFFF5F3F7);
  static const textSecondary = Color(0xFFA9A3B5);
  static const divider = Color(0xFF3A3545);
}

class StudioRadius {
  static const card = 16.0;
  static const input = 12.0;
  static const pill = 999.0;
}

class StudioSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

ThemeData buildStudioTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: StudioColors.neon,
    brightness: Brightness.dark,
    primary: StudioColors.neon,
    secondary: StudioColors.amber,
    tertiary: StudioColors.teal,
    error: StudioColors.error,
    surface: StudioColors.background,
    onSurface: StudioColors.textPrimary,
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(StudioRadius.input),
    borderSide: const BorderSide(color: StudioColors.divider),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: StudioColors.background,
    cardTheme: CardThemeData(
      color: StudioColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioRadius.card),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: StudioColors.surface,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: StudioColors.neon, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: StudioColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioRadius.pill),
      ),
    ),
    dividerColor: StudioColors.divider,
  );
}
