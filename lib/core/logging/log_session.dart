import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';

/// App-wide log session info. Single instance, created at startup.
///
/// Kept dependency-free on purpose: no `package_info_plus` / `device_info_plus`.
/// `app_version` is sourced from [AppConfig.embyClientVersion] so the value
/// always matches what we already send to Emby and what's in `pubspec.yaml`.
class LogSession {
  LogSession._({
    required this.sessionId,
    required this.platform,
    required this.appVersion,
    required this.startedAt,
  });

  /// Created exactly once on first access.
  static LogSession? _instance;

  static LogSession get instance => _instance ??= _create();

  /// 4-hex short id, stable for the lifetime of the process.
  final String sessionId;

  /// One of `windows` / `android` / `ios` / `macos` / `linux` / `fuchsia` / `web`.
  final String platform;

  /// Matches `pubspec.yaml` `version:` via [AppConfig.embyClientVersion].
  final String appVersion;

  /// Process start time (used for "app uptime" in reports).
  final DateTime startedAt;

  static LogSession _create() {
    final rand = Random();
    final id = rand.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    final plat = kIsWeb
        ? 'web'
        : Platform.operatingSystem; // android / windows / linux / macos / ios / fuchsia
    return LogSession._(
      sessionId: id,
      platform: plat,
      appVersion: AppConfig.embyClientVersion,
      startedAt: DateTime.now(),
    );
  }

  /// One-line banner written at log init time so every file starts with
  /// "what app, what version, what platform" — diagnostics first thing visible.
  String banner() {
    final osVer = kIsWeb ? '' : ' os_ver=${Platform.operatingSystemVersion}';
    return 'session=$sessionId app=${AppConfig.appName} ver=$appVersion '
        'platform=$platform$osVer dart=${Platform.version.split(' ').first}';
  }
}
