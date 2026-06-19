import 'package:flutter/material.dart';

/// Fixed neutral [ColorScheme] layers — independent of user accent variant.
///
/// StreamLux design (`#131315` dark / light grey page). Surfaces do not shift
/// when the user picks indigo, amber, etc.
abstract final class AppNeutralScheme {
  static ColorScheme forBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? _dark : _light;
  }

  static final ColorScheme _dark = ColorScheme.dark(
    surface: const Color(0xFF131315),
    onSurface: const Color(0xFFE5E1E4),
    // Neutral secondary text — not StreamLux amber (#d5c4ab); accent stays in primary.
    onSurfaceVariant: const Color(0xFF9898A2),
    surfaceContainerLowest: const Color(0xFF0E0E10),
    surfaceContainerLow: const Color(0xFF1B1B1D),
    surfaceContainer: const Color(0xFF1F1F21),
    surfaceContainerHigh: const Color(0xFF2A2A2C),
    surfaceContainerHighest: const Color(0xFF353437),
    outline: const Color(0xFF6E6E78),
    outlineVariant: const Color(0xFF3A3A40),
    secondary: const Color(0xFFC8C6C8),
    onSecondary: const Color(0xFF303032),
    secondaryContainer: const Color(0xFF474649),
    onSecondaryContainer: const Color(0xFFB7B4B7),
    tertiary: const Color(0xFFE0E1E1),
    onTertiary: const Color(0xFF2F3131),
    tertiaryContainer: const Color(0xFFC4C5C5),
    onTertiaryContainer: const Color(0xFF505252),
    error: const Color(0xFFFFB4AB),
    onError: const Color(0xFF690005),
    errorContainer: const Color(0xFF93000A),
    onErrorContainer: const Color(0xFFFFDAD6),
    inverseSurface: const Color(0xFFE5E1E4),
    onInverseSurface: const Color(0xFF303032),
  ).copyWith(surfaceTint: Colors.transparent);

  static final ColorScheme _light = ColorScheme.light(
    surface: const Color(0xFFF5F5F7),
    onSurface: const Color(0xFF1A1A1E),
    onSurfaceVariant: const Color(0xFF5C5C66),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow: const Color(0xFFF0F0F4),
    surfaceContainer: const Color(0xFFE8E8ED),
    surfaceContainerHigh: const Color(0xFFE0E0E6),
    surfaceContainerHighest: const Color(0xFFD4D4DC),
    outline: const Color(0xFF8E8E98),
    outlineVariant: const Color(0xFFC8C8D2),
    secondary: const Color(0xFF5C5C66),
    onSecondary: const Color(0xFFFFFFFF),
    secondaryContainer: const Color(0xFFE8E8ED),
    onSecondaryContainer: const Color(0xFF3A3A42),
    tertiary: const Color(0xFF5C5C66),
    onTertiary: const Color(0xFFFFFFFF),
    tertiaryContainer: const Color(0xFFE8E8ED),
    onTertiaryContainer: const Color(0xFF3A3A42),
    error: const Color(0xFFC62828),
    onError: const Color(0xFFFFFFFF),
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF690005),
    inverseSurface: const Color(0xFF1A1A1E),
    onInverseSurface: const Color(0xFFF5F5F7),
  ).copyWith(surfaceTint: Colors.transparent);
}
