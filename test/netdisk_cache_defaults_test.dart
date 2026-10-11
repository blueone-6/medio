import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/layout/platform_layout.dart';
import 'package:media_client/core/player/netdisk_cache_defaults.dart';

void main() {
  group('defaultNetdiskCacheEnabled', () {
    test('enabled on desktop and phones/tablets', () {
      expect(defaultNetdiskCacheEnabled(DeviceType.desktop), isTrue);
      expect(defaultNetdiskCacheEnabled(DeviceType.phone), isTrue);
      expect(defaultNetdiskCacheEnabled(DeviceType.tablet), isTrue);
    });

    test('disabled on TV (small storage)', () {
      expect(defaultNetdiskCacheEnabled(DeviceType.tv), isFalse);
    });
  });

  group('defaultNetdiskCacheLimitMb', () {
    test('per-platform caps', () {
      expect(defaultNetdiskCacheLimitMb(DeviceType.desktop), 5120);
      expect(defaultNetdiskCacheLimitMb(DeviceType.phone), 2048);
      expect(defaultNetdiskCacheLimitMb(DeviceType.tablet), 2048);
      expect(defaultNetdiskCacheLimitMb(DeviceType.tv), 1024);
    });
  });
}
