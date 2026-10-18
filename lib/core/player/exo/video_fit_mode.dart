/// Video scaling modes exposed to the user (ExoPlayer, phone and TV).
///
/// Only the three behaviours that are actually distinguishable on a full-screen
/// surface are offered. media3's `RESIZE_MODE_FIXED_WIDTH` / `FIXED_HEIGHT` are
/// deliberately omitted: with a fixed viewport and a fixed frame aspect they
/// collapse onto [zoom] / [fit] (locking the width scales the frame past the
/// viewport height → identical to cover; locking the height letterboxes the
/// sides → identical to fit), which made two of the five entries look broken.
///
/// Verified against media3-ui 1.4.1:
/// `FIT = 0`, `FIXED_WIDTH = 1`, `FIXED_HEIGHT = 2`, `FILL = 3`, `ZOOM = 4`.
library;

enum VideoFitMode {
  /// Whole frame visible, bars fill the remainder (`RESIZE_MODE_FIT`).
  fit,

  /// Upscale until the frame covers the viewport, cropping the overflow.
  /// Aspect preserved (`RESIZE_MODE_ZOOM`).
  zoom,

  /// Stretch to exactly fill the viewport — distorts the picture
  /// (`RESIZE_MODE_FILL`).
  fill;

  /// Media3 `AspectRatioFrameLayout.RESIZE_MODE_*` value.
  int get nativeValue => switch (this) {
        VideoFitMode.fit => 0, // RESIZE_MODE_FIT
        VideoFitMode.fill => 3, // RESIZE_MODE_FILL
        VideoFitMode.zoom => 4, // RESIZE_MODE_ZOOM
      };

  String get label => switch (this) {
        VideoFitMode.fit => '适应',
        VideoFitMode.zoom => '裁剪铺满',
        VideoFitMode.fill => '拉伸填满',
      };

  /// Short label for the compact controls bar.
  String get shortLabel => switch (this) {
        VideoFitMode.fit => '适应',
        VideoFitMode.zoom => '裁剪',
        VideoFitMode.fill => '拉伸',
      };

  /// One-line explanation shown in the tooltip.
  String get description => switch (this) {
        VideoFitMode.fit => '完整画面，可能留黑边',
        VideoFitMode.zoom => '等比例放大铺满，边缘可能被裁',
        VideoFitMode.fill => '非等比拉伸填满（画面会变形）',
      };

  /// Next mode when the user taps the picture button.
  VideoFitMode get next => switch (this) {
        VideoFitMode.fit => VideoFitMode.zoom,
        VideoFitMode.zoom => VideoFitMode.fill,
        VideoFitMode.fill => VideoFitMode.fit,
      };

  /// Persistence helpers. Unset/unknown values fall back to [VideoFitMode.zoom]
  /// (等比例铺满 — the confirmed default); names of modes that no longer exist
  /// (e.g. the dropped fixedWidth/fixedHeight) also land there.
  static VideoFitMode fromName(String? name) {
    for (final m in VideoFitMode.values) {
      if (m.name == name) return m;
    }
    return VideoFitMode.zoom;
  }
}

/// Which mode can actually be used in the current orientation.
///
/// Portrait already fills the width with a landscape frame, and every
/// crop-like mode would then scale the frame up by ~4x (2800/709) and throw
/// away most of the picture — so portrait always renders [VideoFitMode.fit].
VideoFitMode effectiveVideoFitMode(
  VideoFitMode mode, {
  required bool landscape,
}) {
  if (!landscape) return VideoFitMode.fit;
  return mode;
}
