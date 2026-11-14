import 'package:flutter/material.dart';

/// Design tokens. Widgets read colours / radii / spacing from here — never
/// hardcode them (same rule as tio-help).
class StudioColors {
  static const neon = Color(0xFFFF4F8B); // 霓虹 pink
  static const amber = Color(0xFFFFB627); // 小巴 amber
  static const teal = Color(0xFF2EC4B6);
  static const brass = Color(0xFFFF8A3D); // horns row in the beat grid
  static const error = Color(0xFFE53935);
  static const background = Color(0xFF0E0D12); // near-black stage
  static const surface = Color(0xFF19171F);
  static const surfaceHigh = Color(0xFF25222D);
  static const glass = Color(0xCC17151D); // mini player and panels over covers
  static const textPrimary = Color(0xFFF5F3F7);
  static const textSecondary = Color(0xFFA9A3B5);
  static const divider = Color(0xFF3A3545);
}

class StudioRadius {
  static const card = 16.0;
  static const input = 12.0;
  static const pill = 999.0;
  static const cover = 12.0;
  static const panel = 20.0;
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
    appBarTheme: const AppBarTheme(
      backgroundColor: StudioColors.background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: StudioColors.textPrimary,
      unselectedLabelColor: StudioColors.textSecondary,
      indicatorColor: StudioColors.neon,
      dividerColor: Colors.transparent,
      tabAlignment: TabAlignment.start,
      labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      activeTrackColor: StudioColors.textPrimary,
      inactiveTrackColor: StudioColors.divider,
      thumbColor: StudioColors.textPrimary,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: StudioColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
