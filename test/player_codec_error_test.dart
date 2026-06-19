import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/player_codec_error.dart';

void main() {
  group('isRecoverablePlayerCodecError', () {
    test('detects mpv decoder init failures', () {
      expect(
        isRecoverablePlayerCodecError(
          "Failed to initialize a decoder for codec 'truehd'.",
        ),
        isTrue,
      );
    });

    test('ignores generic network errors', () {
      expect(
        isRecoverablePlayerCodecError('tcp: connection reset'),
        isFalse,
      );
    });
  });

  group('playerCodecErrorFinalMessage', () {
    test('maps TrueHD to user-facing copy', () {
      expect(
        playerCodecErrorFinalMessage(
          "Failed to initialize a decoder for codec 'truehd'.",
        ),
        contains('音频格式'),
      );
    });
  });
}
