import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';

// Native mpv backend only; not part of the public media_kit API.
// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/real.dart' as native;

/// Applies subtitle timing offset via mpv `sub-delay` (seconds).
///
/// Positive [delay] shows subtitles later; negative shows them earlier.
extension PlayerSubtitleDelay on Player {
  Future<void> setSubtitleDelay(Duration delay) async {
    if (kIsWeb) return;
    final platform = this.platform;
    if (platform is! native.NativePlayer) return;

    final seconds = delay.inMilliseconds / 1000.0;
    await platform.setProperty('sub-delay', seconds.toString());
  }
}
