import 'dart:ui' show Rect;

import 'package:media_kit/media_kit.dart';

/// Uses the controller's real display rect (dw/dh after aspect correction and
/// rotation — the same size media_kit's FittedBox uses), then decoded
/// [VideoParams], then item metadata.
double subtitleLetterboxBottomForVideo({
  required double viewportWidth,
  required double viewportHeight,
  Rect? videoRect,
  VideoParams? params,
  int? fallbackWidth,
  int? fallbackHeight,
}) {
  final rw = videoRect?.width;
  final rh = videoRect?.height;
  if (rw != null && rh != null && rw > 0 && rh > 0) {
    return subtitleLetterboxBottom(
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      w: rw.round(),
      h: rh.round(),
    );
  }
  if (params != null) {
    return subtitleLetterboxBottomForParams(
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      params: params,
      fallbackWidth: fallbackWidth,
      fallbackHeight: fallbackHeight,
    );
  }
  return subtitleLetterboxBottom(
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    w: fallbackWidth,
    h: fallbackHeight,
  );
}

/// Uses media metadata before mpv reports decoded dimensions, then delegates
/// to [subtitleLetterboxBottom].
double subtitleLetterboxBottomForParams({
  required double viewportWidth,
  required double viewportHeight,
  required VideoParams params,
  int? fallbackWidth,
  int? fallbackHeight,
}) {
  final hasDecodedDimensions =
      (params.aspect != null && params.aspect! > 0) ||
          (params.dw != null &&
              params.dw! > 0 &&
              params.dh != null &&
              params.dh! > 0) ||
          (params.w != null &&
              params.w! > 0 &&
              params.h != null &&
              params.h! > 0);

  return subtitleLetterboxBottom(
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    aspect: params.aspect,
    dw: params.dw,
    dh: params.dh,
    w: hasDecodedDimensions ? params.w : fallbackWidth,
    h: hasDecodedDimensions ? params.h : fallbackHeight,
  );
}
/// Bottom black-bar height of the letterbox that `BoxFit.contain` leaves
/// below the video frame for a `viewportWidth × viewportHeight` viewport.
///
/// The Flutter [SubtitleView] overlay is anchored to the *screen* bottom, but
/// on a portrait (or otherwise non-matching) viewport the video is letterboxed
/// with black bars above/below, so anchoring subtitles to the screen bottom
/// drops them into the bar — far from the video. This offset re-anchors them
/// just above the video frame's bottom edge.
double subtitleLetterboxBottom({
  required double viewportWidth,
  required double viewportHeight,
  double? aspect,
  int? dw,
  int? dh,
  int? w,
  int? h,
}) {
  if (viewportWidth <= 0 || viewportHeight <= 0) return 0;

  final videoAspect = (aspect != null && aspect > 0)
      ? aspect
      : (dw != null && dw > 0 && dh != null && dh > 0)
          ? dw / dh
          : (w != null && w > 0 && h != null && h > 0)
              ? w / h
              : null;
  if (videoAspect == null || videoAspect <= 0) return 0;

  final viewportAspect = viewportWidth / viewportHeight;
  // Video narrower than the viewport → letterbox above/below. When the video
  // is wider (or equal), `BoxFit.contain` letterboxes the sides instead and
  // the bottom bar is zero.
  if (viewportAspect < videoAspect) {
    final videoHeight = viewportWidth / videoAspect;
    return (viewportHeight - videoHeight) / 2;
  }
  return 0;
}
