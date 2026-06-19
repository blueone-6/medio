import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

import '../layout/platform_layout.dart';
import '../logging/app_log.dart';

const _channel = MethodChannel('media_client/device');

/// 启动时探测 Android TV（leanback / UI_MODE_TYPE_TELEVISION），结果写入
/// [setAndroidTvDetected]，从而激活全局 `deviceType == tv` 分支。
///
/// 非 Android 平台直接跳过。
Future<void> detectAndroidTv() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final isTv = await _channel.invokeMethod<bool>('isAndroidTv') ?? false;
    setAndroidTvDetected(isTv);
    AppLog.instance.i('tv_detection', 'isAndroidTv=$isTv');
  } catch (e) {
    // 通道不可用时按非 TV 处理，不阻塞启动。
    AppLog.instance.w('tv_detection', 'detect failed: $e');
  }
}
