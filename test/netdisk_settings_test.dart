import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/layout/platform_layout.dart';
import 'package:media_client/core/storage/local_storage.dart';
import 'package:media_client/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('netdisk cache defaults follow device type', () async {
    final storage = await LocalStorage.open();
    final s = SettingsService(storage);
    expect(s.netdiskCacheEnabledFor(DeviceType.tv), isFalse);
    expect(s.netdiskCacheEnabledFor(DeviceType.desktop), isTrue);
    expect(s.netdiskCacheLimitMbFor(DeviceType.desktop), 5120);
    expect(s.netdiskCacheLimitMbFor(DeviceType.phone), 2048);
    expect(s.netdiskCacheLimitMbFor(DeviceType.tv), 1024);
  });

  test('netdisk cache overrides persist and clamp', () async {
    final storage = await LocalStorage.open();
    final s = SettingsService(storage);
    await s.setNetdiskCacheEnabled(true);
    await s.setNetdiskCacheLimitMb(30000);
    expect(s.netdiskCacheEnabledFor(DeviceType.tv), isTrue);
    expect(
      s.netdiskCacheLimitMbFor(DeviceType.tv),
      SettingsService.netdiskCacheLimitMbMax,
    );
    await s.setNetdiskCacheLimitMb(-5);
    expect(s.netdiskCacheLimitMbFor(DeviceType.tv),
        SettingsService.netdiskCacheLimitMbMin);
  });
}
