import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';
import 'home_layout.dart';

/// Stitch glass tokens — dark defaults with theme-aware helpers for light mode.
abstract final class HomeGlassTokens {
  /// `glass-panel` fill: rgba(255, 255, 255, 0.05)
  static const panelFillDark = Color(0x0DFFFFFF);

  static const borderWidth = 1.0;

  /// Opaque `glass-border` composited on `#131315` — stable rim, no poster bleed-through.
  static const mediaRimSolidDark = Color(0xFF3E3E46);

  /// Media card / glass-panel stroke (opaque in dark theme).
  static Color mediaCardRim(ColorScheme cs) => cs.brightness == Brightness.dark
      ? mediaRimSolidDark
      : cs.outlineVariant.withValues(alpha: 0.55);

  static Color rimBorder(ColorScheme cs) => mediaCardRim(cs);

  static double mediaRestOpacity(ColorScheme cs, double darkValue) =>
      cs.brightness == Brightness.dark ? darkValue : 1.0;

  static double mediaUniformDarken(ColorScheme cs, double amount) =>
      cs.brightness == Brightness.dark ? amount : 0.0;

  static bool usePosterBlur(ColorScheme cs) =>
      cs.brightness == Brightness.dark;

  static Color badgeFill(ColorScheme cs) => Colors.black.withValues(
        alpha: cs.brightness == Brightness.dark ? 0.60 : 0.55,
      );

  /// Rating pill — heavier scrim so theme accent stays legible on posters.
  static Color ratingBadgeFill(ColorScheme cs) => Colors.black.withValues(
        alpha: cs.brightness == Brightness.dark ? 0.72 : 0.68,
      );

  static Color badgeBorder(ColorScheme cs) => cs.brightness == Brightness.dark
      ? mediaRimSolidDark
      : Colors.white.withValues(alpha: 0.22);

  static const badgeForeground = Colors.white;

  /// Star + score on media cards — follows user accent variant.
  static Color ratingBadgeForeground(ColorScheme cs) => cs.primary;

  /// Secondary line on poster scrim (episode progress, genre/year, etc.).
  static Color posterMetaForeground(ColorScheme cs) => cs.brightness == Brightness.dark
      ? cs.onSurface.withValues(alpha: 0.90)
      : cs.onSurface.withValues(alpha: 0.78);

  static Color ratingBadgeBorder(ColorScheme cs) =>
      cs.primary.withValues(alpha: cs.brightness == Brightness.dark ? 0.38 : 0.45);

  /// Glass play control on poster imagery — high contrast in both themes.
  static Color playControlFill(ColorScheme cs) =>
      Colors.black.withValues(alpha: 0.68);

  static Color playControlBorder(ColorScheme cs) =>
      Colors.white.withValues(alpha: cs.brightness == Brightness.dark ? 0.32 : 0.42);

  static Color playControlIcon(ColorScheme cs, {required bool filled}) {
    if (filled) return cs.onPrimary;
    return badgeForeground;
  }

  static List<BoxShadow>? rimShadow(ColorScheme cs) {
    if (cs.brightness == Brightness.dark) return null;
    return [
      BoxShadow(
        color: Color.alphaBlend(
          cs.primary.withValues(alpha: 0.06),
          cs.shadow.withValues(alpha: 0.12),
        ),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ];
  }

  /// Continue-watching / backdrop cards — title on image overlay.
  static Color backdropTitleForeground(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? cs.onSurface : badgeForeground;

  static Color backdropMetaForeground(ColorScheme cs) =>
      cs.brightness == Brightness.dark
          ? posterMetaForeground(cs)
          : Colors.white.withValues(alpha: 0.88);

  static Color backdropProgressTrack(ColorScheme cs) =>
      cs.brightness == Brightness.dark
          ? cs.surfaceContainer
          : Colors.white.withValues(alpha: 0.32);

  static Color backdropGlassButtonFill(ColorScheme cs) =>
      cs.brightness == Brightness.dark
          ? panelFillDark
          : Colors.white.withValues(alpha: 0.14);

  static Color backdropGlassButtonBorder(ColorScheme cs) =>
      cs.brightness == Brightness.dark
          ? mediaRimSolidDark
          : Colors.white.withValues(alpha: 0.28);

  static Color backdropGlassButtonLabel(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? cs.onSurface : badgeForeground;
}

enum HomeMediaScrimShape { poster, hero, secondary }

/// Emby-style dark bottom scrim for media cards (continue-watching & recommend).
///
/// Keeps artwork vivid while legibility comes from light text on a dark fade,
/// regardless of app theme brightness.
BoxDecoration homeMediaBackdropScrim(HomeMediaScrimShape shape) {
  return switch (shape) {
    HomeMediaScrimShape.hero => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.82),
            Colors.black.withValues(alpha: 0.40),
            Colors.black.withValues(alpha: 0.10),
            Colors.transparent,
          ],
          stops: const [0.0, 0.40, 0.62, 1.0],
        ),
      ),
    HomeMediaScrimShape.secondary => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.86),
            Colors.black.withValues(alpha: 0.46),
            Colors.transparent,
          ],
          stops: const [0.0, 0.50, 0.80],
        ),
      ),
    HomeMediaScrimShape.poster => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.80),
            Colors.transparent,
            Colors.transparent,
          ],
          stops: const [0.0, 0.38, 1.0],
        ),
      ),
  };
}

/// Stitch `glass-panel` — clipped media with an opaque rim painted above the edge.
///
/// Semi-transparent borders and backdrop blur pick up poster hues; the rim is a
/// fixed neutral stroke so it matches the design draft on any artwork.
class HomeGlassPanel extends StatelessWidget {
  const HomeGlassPanel({
    super.key,
    required this.borderRadius,
    required this.child,
  });

  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rim = HomeGlassTokens.mediaCardRim(cs);

    Widget panel = ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: rim,
                    width: HomeGlassTokens.borderWidth,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final shadow = HomeGlassTokens.rimShadow(cs);
    if (shadow != null) {
      panel = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: shadow,
        ),
        child: panel,
      );
    }

    return panel;
  }
}

/// Hover-animated background for media cards.
///
/// Uses one [AnimationController] so scale, opacity, and darken stay in sync.
/// Only the poster layer scales; scrim/overlays stay fixed (Stitch `img` hover).
class HoverAnimatedBackground extends StatefulWidget {
  const HoverAnimatedBackground({
    super.key,
    required this.image,
    required this.scrim,
    required this.hovered,
    this.restOpacity = 0.8,
    this.hoverOpacity = 1.0,
    this.restDarken = 0.08,
    this.hoverDarken = 0.0,
    this.hoverScale = 1.05,
    this.scaleDuration = const Duration(milliseconds: 500),
  });

  final Widget image;
  final Decoration? scrim;
  final ValueNotifier<bool> hovered;
  final double restOpacity;
  final double hoverOpacity;
  final double restDarken;
  final double hoverDarken;
  final double hoverScale;
  final Duration scaleDuration;

  @override
  State<HoverAnimatedBackground> createState() => _HoverAnimatedBackgroundState();
}

class _HoverAnimatedBackgroundState extends State<HoverAnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.scaleDuration,
      value: widget.hovered.value ? 1.0 : 0.0,
    );
    widget.hovered.addListener(_onHoverChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration =
        AppMotion.effectiveDuration(context, widget.scaleDuration);
  }

  @override
  void didUpdateWidget(covariant HoverAnimatedBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hovered != widget.hovered) {
      oldWidget.hovered.removeListener(_onHoverChanged);
      widget.hovered.addListener(_onHoverChanged);
      _onHoverChanged();
    }
    final duration = AppMotion.effectiveDuration(context, widget.scaleDuration);
    if (_controller.duration != duration) {
      _controller.duration = duration;
    }
  }

  void _onHoverChanged() {
    if (!mounted) return;
    if (!AppMotion.animationsEnabled(context)) {
      _controller.value = widget.hovered.value ? 1.0 : 0.0;
      return;
    }
    if (widget.hovered.value) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    widget.hovered.removeListener(_onHoverChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final restDarken =
        HomeGlassTokens.mediaUniformDarken(cs, widget.restDarken);
    final hoverDarken =
        HomeGlassTokens.mediaUniformDarken(cs, widget.hoverDarken);

    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        child: RepaintBoundary(child: widget.image),
        builder: (context, imageChild) {
          final motion = AppMotion.animationsEnabled(context);
          final t = Curves.easeOut.transform(_controller.value);
          final scale = motion ? lerpDouble(1.0, widget.hoverScale, t)! : 1.0;
          final opacity = lerpDouble(widget.restOpacity, widget.hoverOpacity, t)!;
          final darken = lerpDouble(restDarken, hoverDarken, t)!;

          return Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: cs.surface),
              Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
                child: Opacity(opacity: opacity, child: imageChild),
              ),
              if (darken > 0)
                ColoredBox(color: Colors.black.withValues(alpha: darken)),
              if (widget.scrim != null)
                DecoratedBox(decoration: widget.scrim!),
            ],
          );
        },
      ),
    );
  }
}

/// Theme-aware glass / elevated surface for home cards.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = HomeLayout.cardRadiusR,
    this.padding,
    this.onTap,
    this.useBlur,
    this.clipChild = true,
    this.rimBorder = false,
    this.depthShadow = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool? useBlur;
  final bool clipChild;
  final bool rimBorder;
  final bool depthShadow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final blur = useBlur ?? (isDark && !rimBorder);

    final fill =
        isDark ? HomeGlassTokens.panelFillDark : cs.surfaceContainerHighest;
    final border = Border.all(
      color: HomeGlassTokens.rimBorder(cs),
      width: HomeGlassTokens.borderWidth,
    );
    final shadow = depthShadow || (!isDark && !rimBorder)
        ? [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.55)
                  : Color.alphaBlend(
                      cs.primary.withValues(alpha: 0.05),
                      cs.shadow.withValues(alpha: 0.16),
                    ),
              blurRadius: isDark ? 10 : 8,
              offset: const Offset(0, 3),
            ),
          ]
        : null;

    Widget inner = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    if (clipChild && !rimBorder) {
      inner = ClipRRect(borderRadius: borderRadius, child: inner);
    }

    Widget content;
    if (rimBorder) {
      content = HomeGlassPanel(
        borderRadius: borderRadius,
        child: inner,
      );
    } else if (blur) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: borderRadius,
              border: border,
            ),
            child: inner,
          ),
        ),
      );
    } else {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: borderRadius,
          border: border,
          boxShadow: shadow,
        ),
        child: inner,
      );
    }

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: content,
        ),
      );
    }
    return content;
  }
}
