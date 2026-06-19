import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/logging/app_log.dart';
import 'core/logging/crash_reporter.dart';
import 'core/logging/perf.dart';
import 'core/storage/local_storage.dart';
import 'core/layout/platform_layout.dart';
import 'core/tv/tv_detection.dart';
import 'providers/settings_provider.dart';
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
    // TV uses ExoPlayer — skip loading libmpv on startup (saves ~100MB+ RAM).
    if (!isAndroidTv) {
      MediaKit.ensureInitialized();
    }

    final storage = await LocalStorage.open();

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
