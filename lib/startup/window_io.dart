import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:window_manager/window_manager.dart';

import '../config/app_config.dart';

Future<void> initDesktopWindow() async {
  if (kIsWeb) return;
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    // Roomy desktop default — 1280×720 felt cramped on 1440p displays.
    size: Size(1600, 960),
    minimumSize: Size(1120, 700),
    center: true,
    title: AppConfig.appName,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
