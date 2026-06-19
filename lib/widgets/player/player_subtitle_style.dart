import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Subtitle overlay config; muxed text uses Flutter overlay ([visible] true), PGS/external use texture.
abstract final class PlayerSubtitleStyle {
  /// Creates a [SubtitleViewConfiguration] with the given [fontSize].
  ///
  /// - Uses [FontWeight.normal] to avoid inconsistent boldness across
  ///   different languages / system fonts.
  /// - Adds a 2-pixel black outline via multiple directional [Shadow]s
  ///   so text remains readable on bright scenes.
  static SubtitleViewConfiguration configuration({
    double fontSize = 48,
    bool visible = true,
  }) {
    const outlineColor = Colors.black;
    const stroke = 2.0;

    return SubtitleViewConfiguration(
      visible: visible,
      style: TextStyle(
        height: 1.2,
        fontSize: fontSize,
        letterSpacing: 0.2,
        color: const Color(0xFFFFFFFF),
        fontWeight: FontWeight.normal,
        backgroundColor: Colors.transparent,
        shadows: const [
          // 8 compass directions + 4 diagonals for a uniform outline
          Shadow(offset: Offset(-stroke, -stroke), blurRadius: 0, color: outlineColor),
          Shadow(offset: Offset(0, -stroke), blurRadius: 0, color: outlineColor),
          Shadow(offset: Offset(stroke, -stroke), blurRadius: 0, color: outlineColor),
          Shadow(offset: Offset(-stroke, 0), blurRadius: 0, color: outlineColor),
          Shadow(offset: Offset(stroke, 0), blurRadius: 0, color: outlineColor),
          Shadow(offset: Offset(-stroke, stroke), blurRadius: 0, color: outlineColor),
          Shadow(offset: Offset(0, stroke), blurRadius: 0, color: outlineColor),
          Shadow(offset: Offset(stroke, stroke), blurRadius: 0, color: outlineColor),
          // Extra diagonals for smoother corners
          Shadow(offset: Offset(-stroke * 0.7, -stroke * 0.7), blurRadius: 0, color: outlineColor),
          Shadow(offset: Offset(stroke * 0.7, -stroke * 0.7), blurRadius: 0, color: outlineColor),
          Shadow(offset: Offset(-stroke * 0.7, stroke * 0.7), blurRadius: 0, color: outlineColor),
          Shadow(offset: Offset(stroke * 0.7, stroke * 0.7), blurRadius: 0, color: outlineColor),
        ],
      ),
      textAlign: TextAlign.center,
      textScaler: const TextScaler.linear(1.15),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 76),
    );
  }
}