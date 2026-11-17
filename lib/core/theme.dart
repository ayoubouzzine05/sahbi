import 'package:material_ui/material_ui.dart';

/// SAHBI palette: near-black blue UI, white robot body, turquoise + green accents.
abstract final class SahbiColors {
  static const background = Color(0xFF060A13);
  static const surface = Color(0xFF0D1422);
  static const surfaceHigh = Color(0xFF142034);
  static const outline = Color(0xFF22324C);
  static const turquoise = Color(0xFF2ED3C6);
  static const green = Color(0xFF3BE38B);
  static const mint = Color(0xFF9BF6E3);
  static const body = Color(0xFFF4F7FA);
  static const bodyShade = Color(0xFFD5DEE7);
  static const visor = Color(0xFF0A0F1A);
  static const coral = Color(0xFFFF6B6B);
  static const amber = Color(0xFFFFC857);
  static const sadBlue = Color(0xFF6FA8FF);
  static const sleepyViolet = Color(0xFF8E8CF0);
  static const textPrimary = Color(0xFFEAF2F8);
  static const textSecondary = Color(0xFF93A4BA);
}

const kFontFamily = 'Tajawal';

ThemeData buildSahbiTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: SahbiColors.turquoise,
        brightness: Brightness.dark,
      ).copyWith(
        primary: SahbiColors.turquoise,
        secondary: SahbiColors.green,
        surface: SahbiColors.surface,
        onSurface: SahbiColors.textPrimary,
        error: SahbiColors.coral,
        outline: SahbiColors.outline,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
    fontFamily: kFontFamily,
    scaffoldBackgroundColor: SahbiColors.background,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: SahbiColors.textPrimary,
    ),
    cardTheme: CardThemeData(
      color: SahbiColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: SahbiColors.outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SahbiColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: SahbiColors.surfaceHigh,
      side: const BorderSide(color: SahbiColors.outline),
      labelStyle: const TextStyle(color: SahbiColors.textPrimary),
      shape: const StadiumBorder(),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
