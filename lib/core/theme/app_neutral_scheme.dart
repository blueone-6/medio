import 'package:flutter/material.dart';

/// Fixed neutral [ColorScheme] layers — independent of user accent variant.
///
/// StreamLux design (`#131315` dark / light grey page). Surfaces do not shift
/// when the user picks indigo, amber, etc.
abstract final class AppNeutralScheme {
  static ColorScheme forBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? _dark : _light;
  }

  static const ColorScheme _dark = ColorScheme.dark(
    surface: Color(0xFF131315),
    onSurface: Color(0xFFE5E1E4),
    // Neutral secondary text — not StreamLux amber (#d5c4ab); accent stays in primary.
    onSurfaceVariant: Color(0xFF9898A2),
    surfaceContainerLowest: Color(0xFF0E0E10),
    surfaceContainerLow: Color(0xFF1B1B1D),
    surfaceContainer: Color(0xFF1F1F21),
    surfaceContainerHigh: Color(0xFF2A2A2C),
    surfaceContainerHighest: Color(0xFF353437),
    outline: Color(0xFF6E6E78),
    outlineVariant: Color(0xFF3A3A40),
    secondary: Color(0xFFC8C6C8),
    onSecondary: Color(0xFF303032),
    secondaryContainer: Color(0xFF474649),
    onSecondaryContainer: Color(0xFFB7B4B7),
    tertiary: Color(0xFFE0E1E1),
    onTertiary: Color(0xFF2F3131),
    tertiaryContainer: Color(0xFFC4C5C5),
    onTertiaryContainer: Color(0xFF505252),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    inverseSurface: Color(0xFFE5E1E4),
    onInverseSurface: Color(0xFF303032),
    surfaceTint: Colors.transparent,
  );

  static const ColorScheme _light = ColorScheme.light(
    surface: Color(0xFFF5F5F7),
    onSurface: Color(0xFF1A1A1E),
    onSurfaceVariant: Color(0xFF5C5C66),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF0F0F4),
    surfaceContainer: Color(0xFFE8E8ED),
    surfaceContainerHigh: Color(0xFFE0E0E6),
    surfaceContainerHighest: Color(0xFFD4D4DC),
    outline: Color(0xFF8E8E98),
    outlineVariant: Color(0xFFC8C8D2),
    secondary: Color(0xFF5C5C66),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE8E8ED),
    onSecondaryContainer: Color(0xFF3A3A42),
    tertiary: Color(0xFF5C5C66),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE8E8ED),
    onTertiaryContainer: Color(0xFF3A3A42),
    error: Color(0xFFC62828),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF690005),
    inverseSurface: Color(0xFF1A1A1E),
    onInverseSurface: Color(0xFFF5F5F7),
    surfaceTint: Colors.transparent,
  );
}
