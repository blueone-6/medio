import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';

// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/real.dart' as native;

/// Unified mpv property read/write extension on [Player].
///
/// Safe to call on any platform — silently no-ops on Web and non-NativePlayer.
extension PlayerMpvProperties on Player {
  /// Sets a string mpv property. Bool values must be `'yes'` / `'no'`.
  Future<void> setMpvProperty(String name, String value) async {
    if (kIsWeb) return;
    final platform = this.platform;
    if (platform is! native.NativePlayer) return;
    await platform.setProperty(name, value);
  }

  /// Reads an mpv property as a string, or null when it is unavailable.
  ///
  /// Used for runtime-only properties (e.g. `audio-delay`) whose value mpv
  /// keeps across chrome rebuilds — the widget cannot.
  Future<String?> getMpvProperty(String name) async {
    if (kIsWeb) return null;
    final platform = this.platform;
    if (platform is! native.NativePlayer) return null;
    try {
      return await platform.getProperty(name, waitForInitialization: false);
    } catch (_) {
      return null;
    }
  }
}
