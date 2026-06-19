import 'package:flutter/material.dart';

import '../../core/theme/app_fonts.dart';

/// Stitch StreamLux typography (`streaming-home-pc-navigation-restored`).
///
/// Latin glyphs use [AppFonts.latinFamily] (Be Vietnam Pro, per Stitch HTML).
/// CJK falls back to [AppFonts.cjkFamily] (Noto Sans SC) when the primary face has no glyph.
abstract final class HomeTypography {
  static const latinFamily = AppFonts.latinFamily;
  static const cjkFamily = AppFonts.cjkFamily;

  static TextStyle _style({
    String? family,
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
    Color? color,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: family ?? latinFamily,
      fontFamilyFallback: AppFonts.fallback,
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  /// `display-lg` — hero title.
  static TextStyle displayLg(Color color) => _style(
        fontSize: 32,
        height: 40 / 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.64,
        color: color,
      );

  /// `headline-lg` — section titles.
  static TextStyle headlineLg(Color color) => _style(
        fontSize: 24,
        height: 32 / 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.24,
        color: color,
      );

  /// `headline-md` + `font-bold` — sidebar brand (Latin logotype).
  static TextStyle headlineMd(Color color) => _style(
        family: latinFamily,
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// `body-md` + `font-medium` — sidebar nav (`14px / 500`).
  static TextStyle navLabel(Color color) => cjkLabel(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w500,
        color: color,
      );

  /// `body-lg` — TV sidebar nav (`16px / 400`, active `700`).
  static TextStyle tvNavLabel(
    Color color, {
    FontWeight fontWeight = FontWeight.w400,
  }) =>
      cjkLabel(
        fontSize: 16,
        height: 24 / 16,
        fontWeight: fontWeight,
        color: color,
      );

  /// Pure CJK labels (sidebar nav) — metrics match Noto Sans SC.
  static TextStyle cjkLabel({
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
    required Color color,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: cjkFamily,
        fontFamilyFallback: const [latinFamily, 'sans-serif'],
        fontSize: fontSize,
        height: height,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        color: color,
        leadingDistribution: TextLeadingDistribution.even,
      );

  /// `body-md` — meta lines, search placeholder.
  static TextStyle bodyMd(Color color) => _style(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        color: color,
      );

  /// `body-md` semibold — recommend poster titles.
  static TextStyle bodyMdSemibold(Color color) => _style(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// Section header trailing action («查看全部», «更多»).
  static Color sectionTrailingLinkColor(
    ColorScheme cs, {
    bool hovered = false,
    bool focused = false,
  }) {
    if (hovered || focused) return cs.onSurface;
    return cs.onSurface.withValues(alpha: 0.82);
  }

  static TextStyle sectionTrailingLink(
    ColorScheme cs, {
    bool hovered = false,
    bool focused = false,
  }) =>
      labelSm(
        sectionTrailingLinkColor(
          cs,
          hovered: hovered,
          focused: focused,
        ),
        fontWeight: FontWeight.w500,
      );

  /// `label-sm` — pills, buttons, trailing links.
  static TextStyle labelSm(
    Color color, {
    FontWeight fontWeight = FontWeight.w500,
  }) =>
      _style(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: fontWeight,
        letterSpacing: 0.24,
        color: color,
      );

  /// `caption-xs` — badges, poster subtitles, brand tagline.
  static TextStyle captionXs(Color color, {FontWeight fontWeight = FontWeight.w500}) => _style(
        fontSize: 10,
        height: 12 / 10,
        fontWeight: fontWeight,
        color: color,
      );
}
