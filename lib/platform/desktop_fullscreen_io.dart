import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:window_manager/window_manager.dart';

Future<bool> _supported() async {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

/// On Windows, `setFullScreen` skips removing the title bar when the window was
/// maximized, and keeps the normal title-bar style — both leave the native chrome
/// visible with gaps around the video. Prepare the window before entering.
Future<void> _prepareWindowsFullscreenEnter() async {
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
}

Future<void> _restoreWindowsWindowChrome() async {
  await windowManager.setTitleBarStyle(TitleBarStyle.normal);
}

Future<bool> desktopIsFullScreen() async {
  if (!await _supported()) return false;
  await windowManager.ensureInitialized();
  return windowManager.isFullScreen();
}

Future<void> desktopSetFullScreen(bool full) async {
  if (!await _supported()) return;
  await windowManager.ensureInitialized();
  if (Platform.isWindows) {
    if (full) {
      await _prepareWindowsFullscreenEnter();
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
      await _restoreWindowsWindowChrome();
    }
    return;
  }
  await windowManager.setFullScreen(full);
}
