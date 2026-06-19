import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import 'glass_surface.dart';
import 'home_typography.dart';

/// Shared metrics so type and rating badges share the same height.
abstract final class HomeBadgeMetrics {
  static const horizontalPadding = 8.0;
  static const verticalPadding = 4.0;
  static const backgroundAlpha = 0.75;
  static const contentLineHeight = 12.0;

  static const strutStyle = StrutStyle(
    fontSize: 10,
    height: 1.2,
    forceStrutHeight: true,
    fontFamily: HomeTypography.cjkFamily,
    fontWeight: FontWeight.w500,
    leading: 0,
  );

  static const ratingStrutStyle = StrutStyle(
    fontSize: 10,
    height: 1.2,
    forceStrutHeight: true,
    fontFamily: HomeTypography.cjkFamily,
    fontWeight: FontWeight.w700,
    leading: 0,
  );

  static const textHeightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );
}

/// Stitch type pill — `bg-black/60 backdrop-blur-md px-2 py-1 rounded`.
class HomeMediaTypeBadge extends StatelessWidget {
  const HomeMediaTypeBadge({
    super.key,
    required this.label,
    this.useBlur = true,
  });

  final String label;
  final bool useBlur;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = HomeTypography.captionXs(HomeGlassTokens.badgeForeground).copyWith(
      letterSpacing: 0.5,
      height: 1.0,
    );

    return _HomeBadgeShell(
      useBlur: useBlur && HomeGlassTokens.usePosterBlur(cs),
      fillColor: HomeGlassTokens.badgeFill(cs),
      borderColor: HomeGlassTokens.ratingBadgeBorder(cs),
      child: Text(
        label,
        textAlign: TextAlign.center,
        textHeightBehavior: HomeBadgeMetrics.textHeightBehavior,
        strutStyle: HomeBadgeMetrics.strutStyle,
        style: textStyle,
      ),
    );
  }
}

/// Rating pill — same footprint as [HomeMediaTypeBadge].
class HomeRatingBadge extends StatelessWidget {
  const HomeRatingBadge({
    super.key,
    required this.label,
    this.useBlur = true,
    this.showStar = true,
  });

  final String label;
  final bool useBlur;
  final bool showStar;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textColor = HomeGlassTokens.ratingBadgeForeground(cs);

    return _HomeBadgeShell(
      useBlur: useBlur && HomeGlassTokens.usePosterBlur(cs),
      fillColor: HomeGlassTokens.ratingBadgeFill(cs),
      borderColor: HomeGlassTokens.ratingBadgeBorder(cs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showStar) ...[
            SizedBox(
              height: HomeBadgeMetrics.contentLineHeight,
              width: 10,
              child: Center(
                child: Icon(Icons.star_rounded, size: 10, color: textColor),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            textHeightBehavior: HomeBadgeMetrics.textHeightBehavior,
            strutStyle: HomeBadgeMetrics.ratingStrutStyle,
            style: HomeTypography.captionXs(textColor, fontWeight: FontWeight.w700).copyWith(
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBadgeShell extends StatelessWidget {
  const _HomeBadgeShell({
    required this.child,
    required this.fillColor,
    required this.borderColor,
    this.useBlur = true,
  });

  final Widget child;
  final Color fillColor;
  final Color borderColor;
  final bool useBlur;

  @override
  Widget build(BuildContext context) {
    Widget badge = DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: AppRadius.xsR,
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HomeBadgeMetrics.horizontalPadding,
          vertical: HomeBadgeMetrics.verticalPadding,
        ),
        child: child,
      ),
    );

    if (!useBlur) return badge;

    return ClipRRect(
      borderRadius: AppRadius.xsR,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: badge,
      ),
    );
  }
}
