import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';

// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/real.dart' as native;
import '../logging/app_log.dart';

/// Deep mpv / media_kit subtitle diagnostics — all output goes to AppLog file.
abstract final class SubtitleDiagnostics {
  static int _traceSeq = 0;

  static int nextTrace() => ++_traceSeq;

  /// mpv properties that explain PGSSUB visibility and [sid] selection.
  static const mpvProbeKeys = [
    'sid',
    'secondary-sid',
    'sub-visibility',
    'secondary-sub-visibility',
    'sub-ass',
    'blend-subtitles',
    'hwdec',
    'hwdec-current',
    'vo',
    'gpu-api',
    'pause',
    'idle-active',
    'duration',
    'time-pos',
    'demuxer-cache-time',
    'video-params',
    'current-tracks',
    'track-list',
    'sub-delay',
    'secondary-sub-delay',
  ];

  static Future<Map<String, String>> readMpvProps(
    Player player, {
    List<String>? keys,
  }) async {
    final out = <String, String>{};
    if (kIsWeb) return out;
    final platform = player.platform;
    if (platform is! native.NativePlayer) {
      out['platform'] = platform.runtimeType.toString();
      return out;
    }
    for (final key in keys ?? mpvProbeKeys) {
      try {
        final v = await platform.getProperty(key, waitForInitialization: false);
        out[key] = v.isEmpty ? '(empty)' : _oneLine(v);
      } catch (e) {
        out[key] = 'ERR:$e';
      }
    }
    return out;
  }

  static String _mediaKitTracksSummary(Player player) {
    final buf = StringBuffer();
    final cur = player.state.track.subtitle;
    buf.writeln(
      'media_kit.current: id=${cur.id} title=${cur.title} lang=${cur.language} '
      'uri=${cur.uri} data=${cur.data} codec=${cur.codec}',
    );
    final lines = player.state.subtitle;
    buf.writeln(
      'media_kit.subtitle_text: primary_len=${lines.isNotEmpty ? lines[0].length : 0} '
      '(non-zero => text/ASS path, PGS usually 0)',
    );
    var i = 0;
    for (final t in player.state.tracks.subtitle) {
      buf.writeln(
        '  [$i] id=${t.id} title=${t.title} lang=${t.language} '
        'codec=${t.codec} default=${t.isDefault} uri=${t.uri} data=${t.data}',
      );
      i++;
    }
    return buf.toString().trimRight();
  }

  static String _playerConfigSummary(Player player) {
    final platform = player.platform;
    if (platform is! native.NativePlayer) {
      return 'platform=${platform.runtimeType}';
    }
    final c = platform.configuration;
    return 'PlayerConfiguration(libass=${c.libass}, '
        'vo=${c.vo}, muted=${c.muted}, bufferSize=${c.bufferSize})';
  }

  /// Full snapshot — call at milestones (open, resume, before/after sid change).
  static Future<void> dump({
    required Player player,
    required String phase,
    int? trace,
    SubtitleTrack? wanted,
    String? extra,
  }) async {
    final t = trace ?? nextTrace();
    final props = await readMpvProps(player);
    final propLines = props.entries.map((e) => '  ${e.key}=${e.value}').join('\n');

    final buf = StringBuffer()
      ..writeln('======== SubtitleDiag trace=$t phase=$phase ========')
      ..writeln(_playerConfigSummary(player));
    if (wanted != null) {
      buf.writeln(
        'wanted: id=${wanted.id} title=${wanted.title} lang=${wanted.language} '
        'codec=${wanted.codec} uri=${wanted.uri} data=${wanted.data}',
      );
    }
    if (extra != null && extra.isNotEmpty) buf.writeln('note: $extra');
    buf.writeln('-- mpv --\n$propLines');
    buf.writeln('-- media_kit --\n${_mediaKitTracksSummary(player)}');
    buf.writeln('======== end trace=$t ========');

    AppLog.instance.i('SubtitleDiag', buf.toString());
  }

  /// After a failed [activateMuxedSubtitle], try every muxed id and log which stick.
  static Future<void> probeAllMuxedSids(
    Player player, {
    required int trace,
  }) async {
    if (kIsWeb) return;
    final platform = player.platform;
    if (platform is! native.NativePlayer) return;

    final muxed = player.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri && !t.data)
        .toList();

    AppLog.instance.w(
      'SubtitleDiag',
      'probeAllMuxedSids trace=$trace count=${muxed.length} — trying each sid',
    );

    for (final t in muxed) {
      await platform.setProperty('sub-visibility', 'yes', waitForInitialization: false);
      try {
        await platform.command(['set', 'sid', t.id], waitForInitialization: false);
      } catch (e) {
        AppLog.instance.w('SubtitleDiag', 'probe set sid=${t.id} command ERR: $e');
        continue;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final sid = await platform.getProperty('sid', waitForInitialization: false);
      final vis =
          await platform.getProperty('sub-visibility', waitForInitialization: false);
      AppLog.instance.i(
        'SubtitleDiag',
        'probe sid=${t.id} title=${t.title} codec=${t.codec} → mpvSid=$sid '
        'sub-visibility=$vis ${sid == t.id ? "OK" : "FAIL"}',
      );
    }

    // Restore strategies
    for (final strategy in ['auto', 'no']) {
      try {
        await platform.command(['set', 'sid', strategy], waitForInitialization: false);
        final sid = await platform.getProperty('sid', waitForInitialization: false);
        AppLog.instance.i('SubtitleDiag', 'probe set sid=$strategy → mpvSid=$sid');
      } catch (e) {
        AppLog.instance.w('SubtitleDiag', 'probe sid=$strategy ERR: $e');
      }
    }

    await dump(player: player, phase: 'after_probeAllMuxedSids', trace: trace);
  }

  static String _oneLine(String s) =>
      s.replaceAll('\r\n', '\\n').replaceAll('\n', '\\n');
}
