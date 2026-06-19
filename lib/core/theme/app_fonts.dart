import 'package:flutter/material.dart';

/// Bundled app typefaces (see `pubspec.yaml` → `flutter.fonts`).
abstract final class AppFonts {
  static const latinFamily = 'BeVietnamPro';
  static const cjkFamily = 'NotoSansSC';
  static const fallback = <String>[cjkFamily, 'sans-serif'];

  /// Apply Latin primary + CJK fallback to a [TextStyle].
  static TextStyle apply(TextStyle style) => style.copyWith(
        fontFamily: latinFamily,
        fontFamilyFallback: fallback,
        leadingDistribution: TextLeadingDistribution.even,
      );

  /// Apply [apply] to every slot in [theme].
  static TextTheme applyToTextTheme(TextTheme theme) => TextTheme(
        displayLarge: theme.displayLarge != null ? apply(theme.displayLarge!) : null,
        displayMedium: theme.displayMedium != null ? apply(theme.displayMedium!) : null,
        displaySmall: theme.displaySmall != null ? apply(theme.displaySmall!) : null,
        headlineLarge: theme.headlineLarge != null ? apply(theme.headlineLarge!) : null,
        headlineMedium: theme.headlineMedium != null ? apply(theme.headlineMedium!) : null,
        headlineSmall: theme.headlineSmall != null ? apply(theme.headlineSmall!) : null,
        titleLarge: theme.titleLarge != null ? apply(theme.titleLarge!) : null,
        titleMedium: theme.titleMedium != null ? apply(theme.titleMedium!) : null,
        titleSmall: theme.titleSmall != null ? apply(theme.titleSmall!) : null,
        bodyLarge: theme.bodyLarge != null ? apply(theme.bodyLarge!) : null,
        bodyMedium: theme.bodyMedium != null ? apply(theme.bodyMedium!) : null,
        bodySmall: theme.bodySmall != null ? apply(theme.bodySmall!) : null,
        labelLarge: theme.labelLarge != null ? apply(theme.labelLarge!) : null,
        labelMedium: theme.labelMedium != null ? apply(theme.labelMedium!) : null,
        labelSmall: theme.labelSmall != null ? apply(theme.labelSmall!) : null,
      );
}
