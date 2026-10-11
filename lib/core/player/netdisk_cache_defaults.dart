import '../layout/platform_layout.dart';

/// Platform defaults for the netdisk disk block cache.
///
/// Desktop has room for a large cache; phones/tables less; Android TV boxes
/// often have very small storage, so caching is off by default there.
bool defaultNetdiskCacheEnabled(DeviceType type) => type != DeviceType.tv;

/// Default cache size cap in MiB for [type].
int defaultNetdiskCacheLimitMb(DeviceType type) {
  switch (type) {
    case DeviceType.desktop:
      return 5120;
    case DeviceType.phone:
    case DeviceType.tablet:
      return 2048;
    case DeviceType.tv:
      return 1024;
  }
}
