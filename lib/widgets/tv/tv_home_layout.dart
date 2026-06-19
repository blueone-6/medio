import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/layout/platform_layout.dart';
import '../home/home_layout.dart';

/// Stitch TV home layout tokens (`streaming-home-tv-focused-ui-refined`).
abstract final class TvHomeLayout {
  /// Stitch TV artboard — sizes scale from this viewport, not content pane width.
  static const designViewportWidth = 1920.0;

  /// Narrower sidebar to leave more room for content on 1080p TV.
  static const sidebarWidth = 200.0;

  static const sidebarPaddingH = 12.0;
  static const sidebarPaddingTop = 24.0;
  static const sidebarBrandGap = 20.0;
  static const sidebarNavGap = 6.0;
  static const sidebarIconSize = 20.0;
  static const sidebarIconGap = 10.0;

  static const designContentPaddingH = 48.0;
  static const designContentPaddingTop = 16.0;
  static const designContentPaddingBottom = 24.0;

  static double contentPaddingLeft(BuildContext context) =>
      math.max(kTvSafeArea, scaled(designContentPaddingH, viewportWidthOf(context)));

  static double contentPaddingRight(BuildContext context) =>
      math.max(kTvSafeArea, scaled(designContentPaddingH, viewportWidthOf(context)));

  static double contentPaddingTop(BuildContext context) {
    final vw = viewportWidthOf(context);
    return scaled(designContentPaddingTop, vw).clamp(20.0, kTvSafeArea);
  }

  static double contentPaddingBottom(BuildContext context) =>
      scaled(designContentPaddingBottom, viewportWidthOf(context));

  static double viewportWidthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static double viewportHeightOf(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  /// Scale design px to the current TV viewport (1080p ≈ 0.56×).
  static double tvScale(double viewportWidth) =>
      (viewportWidth / designViewportWidth).clamp(0.55, 1.0);

  static double scaled(double designPx, double viewportWidth) =>
      designPx * tvScale(viewportWidth);

  /// Gap between continue / recommend sections (tight for one-screen home).
  static const designSectionGap = 20.0;

  static double sectionGapFor(double viewportWidth) =>
      scaled(designSectionGap, viewportWidth);

  static const designSectionHeaderGap = 12.0;

  static double sectionHeaderGapFor(double viewportWidth) =>
      scaled(designSectionHeaderGap, viewportWidth);

  /// Section titles (`继续观看` / `为你推荐`).
  static const designSectionTitleSize = 28.0;
  static const designSectionTitleLineHeight = 36.0;

  static double sectionTitleSizeFor(double viewportWidth) =>
      scaled(designSectionTitleSize, viewportWidth);

  static double sectionTitleLineHeightFor(double viewportWidth, double fontSize) =>
      scaled(designSectionTitleLineHeight, viewportWidth) / fontSize;

  /// Trim line-box padding so section titles baseline-align with trailing controls.
  static const sectionHeaderTextBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  /// Extra space between「继续观看」title and hero card.
  static const designContinueTitleHeroGap = 22.0;

  static double continueTitleHeroGapFor(double viewportWidth) =>
      scaled(designContinueTitleHeroGap, viewportWidth);

  /// Continue hero (`w-[600px] aspect-[3/2]` in Stitch TV).
  static const designContinueHeroWidth = 640.0;
  static const designContinueHeroAspect = 3 / 2;
  static const designContinueHeroMaxHeight = 335.0;
  static const designContinueRowGap = 48.0;
  /// Share of viewport height reserved for the continue block (header + row).
  static const continueViewportHeightFraction = 0.44;
  static const designHeroTitleSize = 48.0;

  static const continueHeroMinWidth = 180.0;
  static const continueMetaMinWidth = 200.0;

  static double continueRowGapFor(double viewportWidth) =>
      scaled(designContinueRowGap, viewportWidth);

  static double continueHeroTitleSizeFor(double viewportWidth) =>
      scaled(designHeroTitleSize, viewportWidth);

  /// Hero size from design scale; height capped so recommend rail fits on one screen.
  /// Minimum content width before the continue hero row can lay out safely.
  static double continueHeroRowMinWidth(double viewportWidth) =>
      continueHeroMinWidth +
      continueRowGapFor(viewportWidth) +
      continueMetaMinWidth;

  /// Row height for hero + secondary column — mirrors PC 21:9, capped for one-screen TV.
  static double continueWideRowHeightFor({
    required double heroContentWidth,
    required double viewportHeight,
    required double secondaryColumnMinHeight,
  }) {
    final natural = heroContentWidth / HomeLayout.pcHeroAspectRatio;
    final budget = viewportHeight * continueViewportHeightFraction;
    return math.min(budget, math.max(natural, secondaryColumnMinHeight));
  }

  static double continueSingleHeroMaxHeight(double viewportHeight) =>
      viewportHeight * continueViewportHeightFraction;

  static ({double width, double height}) continueHeroSizeFor({
    required double contentWidth,
    required double viewportWidth,
    double? maxHeight,
  }) {
    if (contentWidth < 48) {
      return (width: 0, height: 0);
    }

    final gap = continueRowGapFor(viewportWidth);
    final targetW = scaled(designContinueHeroWidth, viewportWidth);
    final maxH = scaled(designContinueHeroMaxHeight, viewportWidth);
    final rowMin = continueHeroRowMinWidth(viewportWidth);

    double width;
    if (contentWidth < rowMin) {
      // Route transitions / RefreshIndicator can briefly squeeze the pane —
      // stack vertically and never exceed the live constraint.
      width = math.min(targetW, contentWidth);
    } else {
      final maxBesideMeta = contentWidth - gap - continueMetaMinWidth;
      width = math.min(targetW, maxBesideMeta).clamp(continueHeroMinWidth, targetW);
    }

    var height = width / designContinueHeroAspect;
    final heightCap = maxHeight == null ? maxH : math.min(maxH, maxHeight);
    if (height > heightCap) {
      height = heightCap;
      width = height * designContinueHeroAspect;
    }
    return (width: width, height: height);
  }

  /// Recommend poster (`w-[200px]`); ~3 cards + peek, title inside the card.
  static const designPosterWidth = 200.0;
  static const posterMinWidth = 100.0;
  static const posterVisibleWithPeek = 3.15;

  static const posterAspect = 2 / 3;

  /// Poster size for TV rail — fills [maxRailHeight] when possible.
  static ({double width, double height}) recommendPosterSize({
    required double contentWidth,
    required double viewportWidth,
    required double maxRailHeight,
  }) {
    if (maxRailHeight <= 0) {
      return (width: 0, height: 0);
    }

    final design = scaled(designPosterWidth, viewportWidth);
    final minW = math.min(posterMinWidth, design);
    final maxWFromPeek =
        (contentWidth - railGap * 2) / posterVisibleWithPeek - railGap;

    // Prefer filling the rail height, then clamp width to peek / design bounds.
    var height = maxRailHeight;
    var width = height * posterAspect;
    if (width > maxWFromPeek) {
      width = maxWFromPeek;
      height = width / posterAspect;
    }
    width = width.clamp(minW, math.max(design, maxWFromPeek));
    height = width / posterAspect;
    if (height > maxRailHeight) {
      height = maxRailHeight;
      width = height * posterAspect;
    }
    return (width: width, height: height);
  }

  /// Horizontal rail gap (`gap-md` = 16px).
  static const railGap = 16.0;

  static const navItemPaddingH = 10.0;
  static const navItemPaddingV = 10.0;

  static const cardRadius = 12.0;
  static const focusBorderWidth = 3.0;
  static const focusScale = 1.05;
  static const focusGlowBlur = 30.0;

  /// Space to reserve so focus border + scale are not clipped by parents.
  static double focusMarginFor(double itemSize, {bool scaleFocused = true}) {
    final scaleOut =
        scaleFocused ? itemSize * (focusScale - 1) / 2 : 0;
    return focusBorderWidth + scaleOut + 2;
  }
}
