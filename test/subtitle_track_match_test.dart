import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_client/core/player/subtitle_track_kind.dart';
import 'package:media_client/core/player/subtitle_track_match.dart';
import 'package:media_client/models/emby/emby_subtitle_option.dart';

SubtitleTrack _muxed({
  required String id,
  String? title,
  String? language,
  String? codec,
  bool? isDefault,
}) {
  return SubtitleTrack(
    id,
    title,
    language,
    codec: codec,
    isDefault: isDefault,
  );
}

void main() {
  group('matchMuxedSubtitleTrack (F1-like muxed list)', () {
    final f1Muxed = [
      _muxed(id: '1', title: 'SDR简英特效', codec: 'hdmv_pgs_subtitle', isDefault: true),
      _muxed(id: '2', title: 'SDR繁英特效', codec: 'hdmv_pgs_subtitle'),
      _muxed(id: '3', title: 'SDR简体特效', codec: 'hdmv_pgs_subtitle'),
      _muxed(id: '4', title: 'SDR繁體特效', codec: 'hdmv_pgs_subtitle'),
      _muxed(id: '5', title: 'HDR简英特效', codec: 'hdmv_pgs_subtitle'),
      _muxed(id: '6', title: 'HDR繁英特效', codec: 'hdmv_pgs_subtitle'),
      _muxed(id: '7', title: 'HDR简体特效', codec: 'hdmv_pgs_subtitle'),
      _muxed(id: '8', title: 'HDR繁體特效', codec: 'hdmv_pgs_subtitle'),
      _muxed(id: '10', title: 'Simplified', codec: 'subrip'),
      _muxed(id: '11', title: 'Traditional', codec: 'subrip'),
      _muxed(id: '9', language: 'eng', codec: 'subrip'),
    ];

    test('maps Chinese Simplified (SUBRIP) to Simplified text track', () {
      final option = EmbySubtitleOption(
        index: 11,
        label: 'Chinese Simplified (SUBRIP)',
        streamUrl: 'http://example/sub/11.srt',
        format: 'srt',
      );
      final m = matchMuxedSubtitleTrack(f1Muxed, option);
      expect(m?.id, '10');
      expect(m?.title, 'Simplified');
    });

    test('maps Chinese Traditional (SUBRIP) to Traditional text track', () {
      final option = EmbySubtitleOption(
        index: 12,
        label: 'Chinese Traditional (SUBRIP)',
        streamUrl: 'http://example/sub/12.srt',
        format: 'srt',
      );
      final m = matchMuxedSubtitleTrack(f1Muxed, option);
      expect(m?.id, '11');
    });

    test('does not map 默认 PGSSUB to first mpv default PGS track by label alone', () {
      final option = EmbySubtitleOption(
        index: 14,
        label: 'Chinese (默认 PGSSUB)',
        streamUrl: 'http://example/sub/14.pgs',
        format: 'pgs',
      );
      final m = matchMuxedSubtitleTrack(f1Muxed, option);
      expect(m, isNull);
    });

    test('PGS sid map keys align with sorted PGS track order (F1 index 6 → sid 5)', () {
      final sidMap = <int, String>{2: '1', 3: '2', 4: '3', 5: '4', 6: '5', 7: '6'};
      final pgs = pgsMuxedSubtitles(f1Muxed).toList()
        ..sort((a, b) => (int.tryParse(a.id) ?? 0).compareTo(int.tryParse(b.id) ?? 0));
      final pgsKeys = sidMap.entries
          .where((e) => pgs.any((t) => t.id == e.value))
          .map((e) => e.key)
          .toList()
        ..sort();
      expect(pgsKeys.indexOf(6), pgs.indexWhere((t) => t.id == '5'));
    });

    test('textMuxedFallbackForPgs picks Simplified for PGSSUB simplified label', () {
      final option = EmbySubtitleOption(
        index: 4,
        label: 'Chinese Simplified (PGSSUB)',
        streamUrl: 'http://example/sub/4.pgs',
        format: 'pgs',
      );
      final m = textMuxedFallbackForPgs(f1Muxed, option);
      expect(m?.id, '10');
    });
  });
}
