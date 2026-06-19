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
}
