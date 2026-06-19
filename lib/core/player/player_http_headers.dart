import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';

import '../../config/app_config.dart';
import '../layout/platform_layout.dart';

// Native mpv backend only; not part of the public media_kit API.
// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/real.dart' as native;

/// Applies HTTP headers and stream tuning on libmpv before opening a remote URL.
extension PlayerPlaybackHttpHeaders on Player {
  Future<void> applyPlaybackHttpHeaders(Map<String, String>? headers) async {
    if (kIsWeb) return;
    final platform = this.platform;
    if (platform is! native.NativePlayer) return;

    if (headers == null || headers.isEmpty) {
      await platform.setProperty('http-header-fields', '');
    } else {
      final value = headers.entries.map((e) => '${e.key}: ${e.value}').join('\r\n');
      await platform.setProperty('http-header-fields', value);
    }
  }

  /// External-CDN playback needs Referer/User-Agent on every byte request
  /// (libavformat level). [headers] supplies the values; pass `null` or an
  /// empty map to clear all overrides.
  Future<void> applyExternalCdnPlaybackOptions(
      {Map<String, String>? headers}) async {
    if (kIsWeb) return;
    final platform = this.platform;
    if (platform is! native.NativePlayer) return;

    if (headers == null || headers.isEmpty) {
      await platform.setProperty('referrer', '');
      await platform.setProperty('user-agent', '');
      await platform.setProperty('http-header-fields', '');
      await platform.setProperty('demuxer-lavf-o', '');
      await platform.setProperty('demuxer-lavf-probesize', '');
      await platform.setProperty('demuxer-lavf-analyzeduration', '');
      return;
    }

    final referer = headers['Referer'] ?? headers['Origin'] ?? '';
    final origin = headers['Origin'] ?? headers['Referer'] ?? '';
    final ua = headers['User-Agent'] ?? AppConfig.httpUserAgent;
    final normalizedHeaders = <String, String>{
      if (referer.isNotEmpty) 'Referer': referer,
      if (origin.isNotEmpty) 'Origin': origin,
      'User-Agent': ua,
    };
    final headerBlock =
        normalizedHeaders.entries.map((e) => '${e.key}: ${e.value}').join('\r\n');

    if (referer.isNotEmpty) await platform.setProperty('referrer', referer);
    await platform.setProperty('user-agent', ua);
    await platform.setProperty('http-header-fields', headerBlock);
    // Do not use stream-lavf-o=headers=… — mpv splits lavf options on commas and
    // Referer URLs contain colons, which breaks header injection for external CDNs.
    await platform.setProperty('demuxer-lavf-o', '');
    await platform.setProperty('demuxer-lavf-probesize', '');
    await platform.setProperty('demuxer-lavf-analyzeduration', '');
  }

  /// Android: prefer audiotrack output (OpenSL can fail silently on some OEM builds).
  Future<void> applyAndroidPlaybackOutput() async {
    if (kIsWeb || !isAndroidMobileUi) return;
    final platform = this.platform;
    if (platform is! native.NativePlayer) return;
    await platform.setProperty('ao', 'audiotrack');
  }

  /// Smaller probe window for Emby proxy streams (fallback path).
  Future<void> applyStreamProbeTuning({required bool enabled}) async {
    if (kIsWeb) return;
    // Tiny probes often fail on Android's network stack; desktop can keep the fast path.
    if (isAndroidMobileUi) {
      enabled = false;
    }
    final platform = this.platform;
    if (platform is! native.NativePlayer) return;
    if (enabled) {
      await platform.setProperty('demuxer-lavf-probesize', '65536');
      await platform.setProperty('demuxer-lavf-analyzeduration', '1');
    } else if (!enabled) {
      await platform.setProperty('demuxer-lavf-probesize', '');
      await platform.setProperty('demuxer-lavf-analyzeduration', '');
    }
  }

  /// Pre-warm the mpv network cache so `set sid` (demuxer cache flush) does not
  /// stall video while re-reading from the HTTP stream.
  ///
  /// `mpv_set_property('sid', ...)` flushes the ffmpeg demuxer cache but the
  /// mpv network-layer cache (raw HTTP bytes) survives.  With [cacheSecs]
  /// seconds pre-buffered the demuxer re-processes cached data instead of
  /// re-fetching over the network.
  Future<void> applyStreamCacheOptions({
    bool enabled = true,
    int cacheSecs = 90,
    String demuxerMaxBytes = '200M',
    int demuxerReadaheadSecs = 90,
  }) async {
    if (kIsWeb) return;
    final platform = this.platform;
    if (platform is! native.NativePlayer) return;
    if (!enabled) {
      await platform.setProperty('cache', 'auto');
      await platform.setProperty('cache-secs', '');
      await platform.setProperty('demuxer-max-bytes', '');
      await platform.setProperty('demuxer-readahead-secs', '');
      return;
    }
    await platform.setProperty('cache', 'yes');
    await platform.setProperty('cache-secs', cacheSecs.toString());
    await platform.setProperty('demuxer-max-bytes', demuxerMaxBytes);
    await platform.setProperty('demuxer-readahead-secs', demuxerReadaheadSecs.toString());
  }
}
