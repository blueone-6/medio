import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/netdisk_recovery.dart';

void main() {
  group('isExpiryStatus', () {
    test('401/403/410 are expiry', () {
      expect(isExpiryStatus(401), isTrue);
      expect(isExpiryStatus(403), isTrue);
      expect(isExpiryStatus(410), isTrue);
    });

    test('others are not', () {
      for (final code in [200, 206, 404, 500, null]) {
        expect(isExpiryStatus(code), isFalse);
      }
    });
  });

  group('shouldReResolve', () {
    test('expiry status with a clean slate re-resolves', () {
      expect(
        shouldReResolve(
          statusCode: 403,
          hasSentBytes: false,
          refreshAttempts: 0,
        ),
        isTrue,
      );
    });

    test('connection failure with a clean slate re-resolves', () {
      expect(
        shouldReResolve(
          connectionFailed: true,
          hasSentBytes: false,
          refreshAttempts: 0,
        ),
        isTrue,
      );
    });

    test('never re-resolves after bytes were sent (no spliced bodies)', () {
      expect(
        shouldReResolve(
          statusCode: 403,
          hasSentBytes: true,
          refreshAttempts: 0,
        ),
        isFalse,
      );
    });

    test('stops after maxRefreshAttempts', () {
      expect(
        shouldReResolve(
          statusCode: 403,
          hasSentBytes: false,
          refreshAttempts: 2,
        ),
        isFalse,
      );
      expect(
        shouldReResolve(
          statusCode: 403,
          hasSentBytes: false,
          refreshAttempts: 1,
        ),
        isTrue,
      );
    });

    test('non-expiry status does not re-resolve', () {
      expect(
        shouldReResolve(
          statusCode: 404,
          hasSentBytes: false,
          refreshAttempts: 0,
        ),
        isFalse,
      );
    });
  });

  group('reResolveDelay', () {
    test('escalates then caps', () {
      expect(reResolveDelay(1), const Duration(milliseconds: 300));
      expect(reResolveDelay(2), const Duration(seconds: 1));
      expect(reResolveDelay(9), const Duration(seconds: 1));
      expect(reResolveDelay(0), const Duration(milliseconds: 300));
    });
  });
}
