import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/dolby_playback.dart';

void main() {
  group('dolbyAudioPassthroughProperties', () {
    test('empty when disabled or not Windows', () {
      expect(
        dolbyAudioPassthroughProperties(windows: false, enabled: true),
        isEmpty,
      );
      expect(
        dolbyAudioPassthroughProperties(windows: true, enabled: false),
        isEmpty,
      );
    });

    test('WASAPI exclusive + spdif codecs on Windows when enabled', () {
      final props = dolbyAudioPassthroughProperties(
        windows: true,
        enabled: true,
      );
      expect(props['ao'], 'wasapi');
      expect(props['audio-exclusive'], 'yes');
      expect(props['audio-spdif'], contains('truehd'));
      expect(props['audio-spdif'], contains('eac3'));
      expect(props['audio-spdif'], contains('dts'));
      expect(props['audio-channels'], 'auto');
    });
  });

  group('dolbyVisionVideoFilter', () {
    test('uses libplacebo to apply DV RPU and tone-map to BT.709', () {
      final vf = dolbyVisionVideoFilter(
        windows: true,
        isDolbyVision: true,
        useLibplacebo: true,
      );
      expect(vf, isNotNull);
      expect(vf, startsWith('lavfi=graph=%${dolbyVisionLibplaceboGraph.length}%'));
      expect(vf, contains('apply_dolbyvision=1'));
      expect(vf, contains('colorspace=bt709'));
      expect(vf, contains('tonemapping=bt.2446a'));
    });

    test('falls back to stripping DV metadata when libplacebo is off', () {
      expect(
        dolbyVisionVideoFilter(
          windows: true,
          isDolbyVision: true,
          useLibplacebo: false,
        ),
        'format:dolbyvision=no',
      );
    });

    test('null for non-DV or non-Windows', () {
      expect(
        dolbyVisionVideoFilter(
          windows: true,
          isDolbyVision: false,
          useLibplacebo: true,
        ),
        isNull,
      );
      expect(
        dolbyVisionVideoFilter(
          windows: false,
          isDolbyVision: true,
          useLibplacebo: true,
        ),
        isNull,
      );
    });
  });
}
