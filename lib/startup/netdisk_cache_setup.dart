import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/layout/platform_layout.dart';
import '../core/logging/app_log.dart';
import '../core/player/netdisk_block_cache.dart';
import '../core/player/netdisk_transport.dart';
import '../services/settings_service.dart';

/// Device type without a [BuildContext] (for startup and settings re-apply).
DeviceType startupDeviceType() {
  if (isAndroidTv) return DeviceType.tv;
  if (isDesktopPlatform) return DeviceType.desktop;
  return DeviceType.phone;
}

Future<Directory> _cacheRoot() async {
  Directory under(Directory base) =>
      Directory('${base.path}${Platform.pathSeparator}netdisk');
  try {
    return under(await getApplicationCacheDirectory());
  } catch (_) {
    return under(await getTemporaryDirectory());
  }
}

/// Builds (or clears) [NetdiskTransport.instance.cache] from [settings].
///
/// Call at startup and whenever the cache settings change. A disabled or
/// zero-sized cache sets `cache` to null so nothing touches the disk.
Future<void> configureNetdiskCache(
  SettingsService settings,
  DeviceType type,
) async {
  final enabled = settings.netdiskCacheEnabledFor(type);
  final limitMb = enabled ? settings.netdiskCacheLimitMbFor(type) : 0;
  if (limitMb <= 0) {
    NetdiskTransport.instance.cache = null;
    AppLog.instance.i('NetdiskCache', 'disabled');
    return;
  }
  try {
    final root = await _cacheRoot();
    final cache = NetdiskBlockCache(
      rootDir: root,
      limitBytes: limitMb * 1024 * 1024,
    );
    await cache.sweep();
    NetdiskTransport.instance.cache = cache;
    AppLog.instance
        .i('NetdiskCache', 'enabled limit=${limitMb}MB dir=${root.path}');
  } catch (e) {
    AppLog.instance.w('NetdiskCache', 'setup failed: $e');
    NetdiskTransport.instance.cache = null;
  }
}
