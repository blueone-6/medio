import 'package:flutter/material.dart';

import 'app_fonts.dart';

/// Shared StreamLux text metrics (used by [AppTextStyles] and [HomeTypography]).
abstract final class AppTypography {
  static TextStyle _base({
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
    Color? color,
    double? letterSpacing,
    String? family,
  }) {
    return TextStyle(
      fontFamily: family ?? AppFonts.latinFamily,
      fontFamilyFallback: AppFonts.fallback,
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  static TextStyle sectionTitle(Color color) => _base(
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: color,
      );

  static TextStyle cardTitle(Color color) => _base(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle cardSubtitle(Color color) => _base(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle cardMeta(Color color) => _base(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle badge(Color color) => _base(
        fontSize: 10,
        height: 1.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: color,
      );

  static TextStyle navLabel(Color color, {bool selected = false}) => _base(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: color,
      );

  static TextStyle displayLg(Color color) => _base(
        fontSize: 32,
        height: 40 / 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.64,
        color: color,
      );

  static TextStyle headlineLg(Color color) => _base(
        fontSize: 24,
        height: 32 / 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.24,
        color: color,
      );
}
