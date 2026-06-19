import 'package:flutter/material.dart';

import 'app_theme_variant.dart';

/// Accent-only tokens merged into the neutral [ColorScheme].
@immutable
class AppAccentTokens {
  const AppAccentTokens({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    this.inversePrimary,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color? inversePrimary;
}

/// Per-variant accent colors with separate dark / light definitions for contrast.
abstract final class AppAccentPalette {
  static AppAccentTokens forVariant(AppThemeVariant variant, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (variant) {
      AppThemeVariant.indigo => isDark ? _indigoDark : _indigoLight,
      AppThemeVariant.teal => isDark ? _tealDark : _tealLight,
      AppThemeVariant.rose => isDark ? _roseDark : _roseLight,
      AppThemeVariant.amber => isDark ? _amberDark : _amberLight,
      AppThemeVariant.purple => isDark ? _purpleDark : _purpleLight,
      AppThemeVariant.cyan => isDark ? _cyanDark : _cyanLight,
      AppThemeVariant.lime => isDark ? _limeDark : _limeLight,
      AppThemeVariant.deepOrange => isDark ? _deepOrangeDark : _deepOrangeLight,
      AppThemeVariant.pureDark => isDark ? _pureDarkDark : _pureDarkLight,
      AppThemeVariant.system => isDark ? _amberDark : _amberLight,
    };
  }

  /// StreamLux cinematic gold (dark) / saturated orange (light).
  static const _amberDark = AppAccentTokens(
    primary: Color(0xFFFFDCA1),
    onPrimary: Color(0xFF412D00),
    primaryContainer: Color(0xFFFFB800),
    onPrimaryContainer: Color(0xFF6B4C00),
    inversePrimary: Color(0xFF7C5800),
  );

  static const _amberLight = AppAccentTokens(
    primary: Color(0xFFE65100),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFE0B2),
    onPrimaryContainer: Color(0xFFBF360C),
    inversePrimary: Color(0xFFFFB74D),
  );

  static const _indigoDark = AppAccentTokens(
    primary: Color(0xFFADB5E8),
    onPrimary: Color(0xFF1A237E),
    primaryContainer: Color(0xFF3F51B5),
    onPrimaryContainer: Color(0xFFE8EAF6),
    inversePrimary: Color(0xFF7986CB),
  );

  static const _indigoLight = AppAccentTokens(
    primary: Color(0xFF3F51B5),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE8EAF6),
    onPrimaryContainer: Color(0xFF1A237E),
    inversePrimary: Color(0xFF5C6BC0),
  );

  static const _tealDark = AppAccentTokens(
    primary: Color(0xFF80CBC4),
    onPrimary: Color(0xFF004D40),
    primaryContainer: Color(0xFF00796B),
    onPrimaryContainer: Color(0xFFE0F2F1),
    inversePrimary: Color(0xFF4DB6AC),
  );

  static const _tealLight = AppAccentTokens(
    primary: Color(0xFF00796B),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFB2DFDB),
    onPrimaryContainer: Color(0xFF004D40),
    inversePrimary: Color(0xFF26A69A),
  );

  static const _roseDark = AppAccentTokens(
    primary: Color(0xFFF48FB1),
    onPrimary: Color(0xFF880E4F),
    primaryContainer: Color(0xFFC2185B),
    onPrimaryContainer: Color(0xFFFCE4EC),
    inversePrimary: Color(0xFFEC407A),
  );

  static const _roseLight = AppAccentTokens(
    primary: Color(0xFFC2185B),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFF8BBD9),
    onPrimaryContainer: Color(0xFF880E4F),
    inversePrimary: Color(0xFFE91E63),
  );

  static const _purpleDark = AppAccentTokens(
    primary: Color(0xFFB388FF),
    onPrimary: Color(0xFF311B92),
    primaryContainer: Color(0xFF7C4DFF),
    onPrimaryContainer: Color(0xFFEDE7F6),
    inversePrimary: Color(0xFF9575CD),
  );

  static const _purpleLight = AppAccentTokens(
    primary: Color(0xFF651FFF),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD1C4E9),
    onPrimaryContainer: Color(0xFF311B92),
    inversePrimary: Color(0xFF7C4DFF),
  );

  static const _cyanDark = AppAccentTokens(
    primary: Color(0xFF80DEEA),
    onPrimary: Color(0xFF006064),
    primaryContainer: Color(0xFF0097A7),
    onPrimaryContainer: Color(0xFFE0F7FA),
    inversePrimary: Color(0xFF26C6DA),
  );

  static const _cyanLight = AppAccentTokens(
    primary: Color(0xFF0097A7),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFB2EBF2),
    onPrimaryContainer: Color(0xFF006064),
    inversePrimary: Color(0xFF00BCD4),
  );

  static const _limeDark = AppAccentTokens(
    primary: Color(0xFFC5E1A5),
    onPrimary: Color(0xFF33691E),
    primaryContainer: Color(0xFF689F38),
    onPrimaryContainer: Color(0xFFF1F8E9),
    inversePrimary: Color(0xFF9CCC65),
  );

  static const _limeLight = AppAccentTokens(
    primary: Color(0xFF689F38),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDCEDC8),
    onPrimaryContainer: Color(0xFF33691E),
    inversePrimary: Color(0xFF8BC34A),
  );

  static const _deepOrangeDark = AppAccentTokens(
    primary: Color(0xFFFFAB91),
    onPrimary: Color(0xFFBF360C),
    primaryContainer: Color(0xFFE64A19),
    onPrimaryContainer: Color(0xFFFBE9E7),
    inversePrimary: Color(0xFFFF7043),
  );

  static const _deepOrangeLight = AppAccentTokens(
    primary: Color(0xFFE64A19),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFCCBC),
    onPrimaryContainer: Color(0xFFBF360C),
    inversePrimary: Color(0xFFFF5722),
  );

  static const _pureDarkDark = AppAccentTokens(
    primary: Color(0xFFB0BEC5),
    onPrimary: Color(0xFF1A1A1A),
    primaryContainer: Color(0xFF37474F),
    onPrimaryContainer: Color(0xFFCFD8DC),
    inversePrimary: Color(0xFF90A4AE),
  );

  static const _pureDarkLight = AppAccentTokens(
    primary: Color(0xFF546E7A),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFCFD8DC),
    onPrimaryContainer: Color(0xFF263238),
    inversePrimary: Color(0xFF78909C),
  );
}
