import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/player/exo/subtitle_text_parse.dart';
import '../../core/player/exo/video_fit_mode.dart';
import '../../core/player/player_subtitle_position.dart';

/// Renders the active external Emby subtitle cue as a Flutter overlay.
///
/// Rendering text subtitles ourselves (instead of a MediaItem sidecar) keeps
/// the full cue timeline client-side, which is what powers both-direction
/// subtitle delay and letterbox-aware positioning on the ExoPlayer path.
class ExoSubtitleOverlay extends StatelessWidget {
  const ExoSubtitleOverlay({
    super.key,
    required this.cues,
    required this.position,
    required this.delayMs,
    required this.fontSizeSetting,
    required this.viewportWidth,
    required this.viewportHeight,
    this.fitMode = VideoFitMode.fit,
    this.videoWidth,
    this.videoHeight,
    this.baseBottomPadding = 24,
  });

  final List<ParsedSubtitleCue> cues;
  final Duration position;
  final int delayMs;

  /// `SettingsService.subtitleFontSize` (42 by default on phones). Media_kit's
  /// SubtitleView scaled this against the video's display size itself; this
  /// overlay must do the same, otherwise the raw number is taken as logical
  /// pixels and lands at ~11% of the screen height on a 3.5x display.
  final double fontSizeSetting;

  /// Overlay viewport (screen) size and the decoded video size, used to
  /// re-anchor the cue above the letterboxed video frame.
  final double viewportWidth;
  final double viewportHeight;
  final VideoFitMode fitMode;
  final int? videoWidth;
  final int? videoHeight;
  final double baseBottomPadding;

  /// Size the configured value is authored for (the phone default).
  static const double _referenceFontSize = 42;

  /// Subtitle line height as a fraction of the displayed video height.
  static const double _heightFraction = 0.055;

  @override
  Widget build(BuildContext context) {
    final cue = activeSubtitleCue(cues, position, delayMs);
    if (cue == null) return const SizedBox.shrink();

    final frameAspect = (videoWidth != null &&
            videoHeight != null &&
            videoWidth! > 0 &&
            videoHeight! > 0)
        ? videoWidth! / videoHeight!
        : (viewportHeight > 0 ? viewportWidth / viewportHeight : 16 / 9);

    // Displayed height of the video frame, in logical pixels. Under fit the
    // frame is letterboxed; under the crop/stretch modes it fills the viewport.
    final displayHeight = fitMode == VideoFitMode.fit
        ? math.min(viewportHeight, viewportWidth / frameAspect)
        : viewportHeight;

    final scale = displayHeight * _heightFraction / _referenceFontSize;
    final fontSize = (_referenceFontSize * scale).clamp(8.0, 64.0) *
        (fontSizeSetting / _referenceFontSize);

    // Subtitle anchored just above the video's bottom edge (letterbox offset
    // only applies when the frame does not already fill the viewport).
    final letterbox = fitMode == VideoFitMode.fit
        ? subtitleLetterboxBottom(
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            w: videoWidth,
            h: videoHeight,
          )
        : 0.0;
    final bottom = baseBottomPadding + letterbox;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 16,
            right: 16,
            bottom: bottom,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 640),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (final line in cue.lines)
                      Text(
                        line,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          height: 1.35,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.9),
                              blurRadius: 4,
                            ),
                            const Shadow(
                              color: Colors.black,
                              offset: Offset(1, 1),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
