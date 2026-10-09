import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';

import '../layout/platform_layout.dart';

// Native mpv backend only; not part of the public media_kit API.
// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/real.dart' as native;

import 'player_http_headers.dart';

/// mpv demuxer prefetch property values for background suspension on Android
/// (absorbed from Kazumi's `setPrefetchSuspended`).
///
/// Android blocks network access for backgrounded apps; a prefetching demuxer
/// then burns through ffmpeg's reconnect/segment retries and marks the stream
/// EOF, leaving playback permanently stuck once the app is foregrounded again.
/// Suspending zeroes the readahead window so no new requests are issued while
/// buffered data stays available; restoring returns [applyStreamCacheOptions]'
/// tuned values (they must stay in sync with its defaults).
Map<String, String> prefetchSuspendMpvProperties({
  required bool suspended,
  int cacheSecs = kStreamCacheSecs,
  int demuxerReadaheadSecs = kStreamDemuxerReadaheadSecs,
}) => {
      'cache-secs': suspended ? '0' : '$cacheSecs',
      'demuxer-readahead-secs': suspended ? '0' : '$demuxerReadaheadSecs',
    };

/// Zeroes / restores the mpv demuxer prefetch window. Callers must serialize
/// writes and apply the latest requested state, so rapid lifecycle flips
/// cannot reorder (see `_setPrefetchSuspended` in the player screen).
extension PlayerPrefetchSuspend on Player {
  Future<void> applyPrefetchSuspend(bool suspended) async {
    if (kIsWeb || !isAndroidMobileUi) return;
    final platform = this.platform;
    if (platform is! native.NativePlayer) return;
    final props = prefetchSuspendMpvProperties(suspended: suspended);
    for (final entry in props.entries) {
      await platform.setProperty(entry.key, entry.value);
    }
  }
}
