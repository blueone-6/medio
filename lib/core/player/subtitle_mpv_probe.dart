import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';

// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/real.dart' as native;
// ignore: implementation_imports
import 'package:media_kit_video/src/utils/query_decoders.dart';

import '../logging/app_log.dart';

/// Logs whether libavcodec exposes PGS / DVD sub decoders in this libmpv build.
Future<void> logMpvSubtitleDecoderSupport(Player player) async {
  if (kIsWeb) return;
  final platform = player.platform;
  if (platform is! native.NativePlayer) return;
  try {
    final handle = await player.handle;
    final decoders = await queryDecoders(handle);
    final pgs = decoders
        .where((d) => d.contains('pgs') || d.contains('dvdsub') || d.contains('pgssub'))
        .toList()
      ..sort();
    final text = decoders
        .where((d) => d.contains('subrip') || d.contains('ass') || d.contains('srt'))
        .toList()
      ..sort();
    AppLog.instance.i(
      'Subtitle',
      'libmpv decoders: pgs_related=${pgs.isEmpty ? "(none)" : pgs.join(",")} '
      'text_related=${text.take(6).join(",")}${text.length > 6 ? "..." : ""}',
    );
    if (pgs.isEmpty) {
      AppLog.instance.w(
        'Subtitle',
        'PGS decoder missing in bundled libmpv; text subtitles will be used as fallback',
        'then rebuild the app.',
      );
    }
  } catch (e, st) {
    AppLog.instance.e('Subtitle', 'decoder-list probe failed', error: e, stackTrace: st);
  }
}
