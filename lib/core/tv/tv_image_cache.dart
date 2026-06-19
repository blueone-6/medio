import 'package:flutter/widgets.dart';

/// TV image decode / Emby request sizing (display-aligned, low memory).
abstract final class TvImageCache {
  static const backdropRequestMaxWidth = 1280;
  static const backdropRequestMaxHeight = 720;

  /// Logical px → device-pixel cache size for [CachedNetworkImage].
  static int memCachePx(BuildContext context, double logicalSize) {
    if (logicalSize <= 0) return 1;
    return (logicalSize * MediaQuery.devicePixelRatioOf(context)).ceil();
  }

  /// Emby poster `maxHeight` aligned to on-screen card size (not 320px default).
  static int posterRequestMaxHeight(double displayHeight) {
    return (displayHeight * 1.25).ceil().clamp(120, 240);
  }

  static const _posterAspect = 2 / 3;

  /// Decode/cache at network-request size — avoids upscaling 240px assets to full DPR grid cells.
  static int memCachePosterHeightPx(BuildContext context, double displayHeight) {
    return memCachePx(context, posterRequestMaxHeight(displayHeight).toDouble());
  }

  static int memCachePosterWidthPx(BuildContext context, double displayHeight) {
    final h = posterRequestMaxHeight(displayHeight).toDouble();
    return memCachePx(context, h * _posterAspect);
  }
}
