import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/logging/app_log.dart';
import 'core/logging/crash_reporter.dart';
import 'core/logging/perf.dart';
import 'core/storage/local_storage.dart';
import 'core/tv/tv_detection.dart';
import 'providers/settings_provider.dart';
import 'services/settings_service.dart';
import 'startup/netdisk_cache_setup.dart';
import 'startup/window_stub.dart' if (dart.library.io) 'startup/window_io.dart' as window;

Future<void> main() async {
  await CrashReporter.runZonedLogged(() async {
    PerfTracer.appStartupSpan = PerfTracer.start('app_startup');
    WidgetsFlutterBinding.ensureInitialized();
    CrashReporter.installGlobalHandlers();
    await AppLog.instance.init();
    await CrashReporter.instance.init();
    await PerfTracer.hydrateFromLogs();
    await window.initDesktopWindow();
    await detectAndroidTv();
    // Android (TV + phone) plays through Media3 ExoPlayer — skip loading
    // libmpv on startup (saves ~100MB+ RAM). Desktop still needs media_kit.
    if (!kIsWeb && !Platform.isAndroid) {
      MediaKit.ensureInitialized();
    }

    final storage = await LocalStorage.open();
    await configureNetdiskCache(SettingsService(storage), startupDeviceType());

    runApp(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWith((ref) => storage),
        ],
        child: const MediaClientApp(),
      ),
    );
  });
}
