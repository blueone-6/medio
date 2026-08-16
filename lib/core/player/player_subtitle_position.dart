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
