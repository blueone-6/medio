import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/player_network_error.dart';

void main() {
  group('isRecoverablePlayerNetworkError', () {
    test('matches ffurl tcp abort from logs', () {
      expect(
        isRecoverablePlayerNetworkError(
          'tcp: ffurl_read returned 0xffffff99',
        ),
        isTrue,
      );
      expect(
        isRecoverablePlayerNetworkError(
          'tcp: ffurl_write returned 0xffffff99',
        ),
        isTrue,
      );
    });

    test('ignores unrelated errors', () {
      expect(
        isRecoverablePlayerNetworkError('decoder error: invalid data'),
        isFalse,
      );
    });
  });
}
