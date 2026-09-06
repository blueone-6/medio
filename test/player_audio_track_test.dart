import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/player_audio_track.dart';
import 'package:media_client/core/player/player_network_error.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  group('audioTrackLabel', () {
    test('combines language and title', () {
      expect(
        audioTrackLabel(const AudioTrack('1', '国语 5.1', 'chi')),
        'chi · 国语 5.1',
      );
    });

    test('language only', () {
      expect(
        audioTrackLabel(const AudioTrack('2', null, 'eng')),
        'eng',
      );
    });

    test('title only', () {
      expect(
        audioTrackLabel(const AudioTrack('3', '评论音轨', '')),
        '评论音轨',
      );
    });

    test('falls back to id when both missing', () {
      expect(
        audioTrackLabel(const AudioTrack('7', null, null)),
        '音轨 7',
      );
    });
  });

  group('playerNetworkErrorFinalMessage', () {
    test('mentions the retry count', () {
      expect(playerNetworkErrorFinalMessage(3), contains('3'));
      expect(playerNetworkErrorFinalMessage(3), contains('网络不稳定'));
    });
  });
}
