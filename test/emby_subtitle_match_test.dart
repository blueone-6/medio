import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:media_client/core/player/emby_subtitle_match.dart';
import 'package:media_client/models/emby/emby_subtitle_option.dart';

SubtitleTrack _muxed({
  required String id,
  String? title,
  String? language,
  String? codec,
  bool external = false,
}) {
  if (external) {
    return SubtitleTrack.uri(id, title: title, language: language);
  }
  return SubtitleTrack(
    id,
    title,
    language,
    codec: codec,
  );
}

const _pgs = EmbySubtitleOption(
  index: 2,
  label: '简体 (PGSSUB)',
  streamUrl: 'http://example/sub/2.pgs',
  format: 'pgs',
);

const _text = EmbySubtitleOption(
  index: 3,
  label: '简体 (SUBRIP)',
  streamUrl: 'http://example/sub/3.srt',
  format: 'srt',
);

const _external = EmbySubtitleOption(
  index: 5,
  label: 'English',
  streamUrl: 'http://example/sub/5.srt',
  format: 'srt',
  isExternal: true,
);

void main() {
  group('embyOptionForSubtitleTrack', () {
    const options = [_pgs, _text, _external];

    test('resolves active PGS track by exact sid via indexTracks', () {
      final cur = _muxed(id: '5', title: 'Chinese', codec: 'hdmv_pgs_subtitle');
      // Emby PGS option index 2 -> mpv sid 5 (exact, no label dependence).
      final indexTracks = <int, SubtitleTrack>{2: cur};
      expect(embyOptionForSubtitleTrack(cur, options, indexTracks)?.index, 2);
      expect(
        embyOptionForSubtitleTrack(cur, options, indexTracks)?.selectionId,
        _pgs.selectionId,
      );
    });

    test('resolves the selected Emby option from the raw mpv sid', () {
      final pgs = _muxed(id: '1', title: 'Chinese', codec: 'hdmv_pgs_subtitle');
      final text = _muxed(id: '10', title: 'Simplified', codec: 'subrip');
      final indexTracks = <int, SubtitleTrack>{2: pgs, 3: text};

      expect(embyOptionForMpvSid('1', options, indexTracks)?.index, 2);
      expect(embyOptionForMpvSid('10', options, indexTracks)?.index, 3);
      expect(embyOptionForMpvSid('no', options, indexTracks), isNull);
    });
    test('resolves active PGS track by label when indexTracks is not ready',
        () {
      final cur =
          _muxed(id: '5', title: '简体特效', codec: 'hdmv_pgs_subtitle');
      expect(embyOptionForSubtitleTrack(cur, options, null)?.index, 2);
    });

    test('does not resolve generic-titled PGS track when map is missing', () {
      // No sid map + label does not match -> no Emby option (no false positive
      // onto the text/external options).
      final cur = _muxed(id: '5', title: 'Chinese', codec: 'hdmv_pgs_subtitle');
      expect(embyOptionForSubtitleTrack(cur, options, null), isNull);
      expect(embyOptionForSubtitleTrack(cur, options, const {}), isNull);
    });

    test('resolves active text track via indexTracks', () {
      final cur = _muxed(id: '10', title: 'Simplified', codec: 'subrip');
      final indexTracks = <int, SubtitleTrack>{3: cur};
      expect(embyOptionForSubtitleTrack(cur, options, indexTracks)?.index, 3);
    });

    test('resolves active external track by url id', () {
      final cur = _muxed(
        id: 'http://example/sub/5.srt?api_key=x',
        title: 'English',
        external: true,
      );
      expect(embyOptionForSubtitleTrack(cur, options, null)?.index, 5);
    });

    test('ignores auto/no tracks', () {
      expect(
        embyOptionForSubtitleTrack(SubtitleTrack.auto(), options, null),
        isNull,
      );
      expect(
        embyOptionForSubtitleTrack(SubtitleTrack.no(), options, null),
        isNull,
      );
    });
  });

  group('subtitleTrackMatchesEmbyOption', () {
    test('matches external by title', () {
      final cur = _muxed(
        id: 'file:///tmp/x.srt',
        title: 'English',
        external: true,
      );
      expect(subtitleTrackMatchesEmbyOption(cur, _external), isTrue);
    });

    test('matches external by streamUrl id', () {
      final cur = _muxed(
        id: 'http://example/sub/5.srt',
        title: 'Other',
        external: true,
      );
      expect(subtitleTrackMatchesEmbyOption(cur, _external), isTrue);
    });

    test('never matches an embedded option against an external track', () {
      final cur = _muxed(
        id: 'file:///tmp/x.srt',
        title: 'English',
        external: true,
      );
      expect(subtitleTrackMatchesEmbyOption(cur, _pgs), isFalse);
      expect(subtitleTrackMatchesEmbyOption(cur, _text), isFalse);
    });
  });
}
