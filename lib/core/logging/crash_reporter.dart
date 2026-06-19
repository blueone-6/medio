import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';
import 'log_session.dart';

/// One parsed crash entry from on-disk crash logs.
class CrashRecord {
  const CrashRecord({
    required this.timestamp,
    required this.source,
    required this.sessionId,
    required this.appVersion,
    required this.platform,
    required this.device,
    required this.message,
    required this.stackTrace,
  });

  final DateTime timestamp;
  final String source;
  final String sessionId;
  final String appVersion;
  final String platform;
  final String device;
  final String message;
  final String stackTrace;

  String get preview {
    final oneLine = message.replaceAll('\n', ' ').trim();
    if (oneLine.length <= 120) return oneLine;
    return '${oneLine.substring(0, 120)}…';
  }
}

/// Writes unhandled errors to dedicated `media_client_crash_*.log` files.
///
/// Reuses [LogSession] for session / version / platform metadata.
/// Regular logging still goes through [AppLog]; this module only handles
/// crash-specific persistence and diagnostics queries.
class CrashReporter {
  CrashReporter._();

  static final CrashReporter instance = CrashReporter._();

  static const _filePrefix = 'media_client_crash_';
  static const _maxFileBytes = 1024 * 1024;
  static const _crashStart = '===== CRASH ';
  static const _crashEnd = '===== END CRASH =====';

  Directory? _logDir;
  String? _activeDate;
  bool _initialized = false;

  String? get crashLogDirectoryPath => _logDir?.path;

  /// Opens the crash log directory. Call after [AppLog.init] when possible.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) return;

    try {
      final existing = AppLog.instance.logDirectoryPath;
      if (existing != null) {
        _logDir = Directory(existing);
      } else {
        final support = await getApplicationSupportDirectory();
        _logDir = Directory('${support.path}${Platform.pathSeparator}logs');
        await _logDir!.create(recursive: true);
      }
      _rotateIfNeededSync();
    } catch (e, st) {
      _logDir = null;
      debugPrint('CrashReporter init failed: $e\n$st');
    }
  }

  /// Installs Flutter / platform error handlers. Call once from [main].
  static void installGlobalHandlers() {
    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      instance.record(
        'FlutterError',
        details.exception,
        details.stack ?? StackTrace.current,
        message: details.exceptionAsString(),
      );
      AppLog.instance.e(
        'FlutterError',
        details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
      );
      prevFlutter?.call(details);
    };

    final prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      instance.record('PlatformDispatcher', error, stack);
      AppLog.instance.e(
        'PlatformDispatcher',
        error.toString(),
        error: error,
        stackTrace: stack,
      );
      return prevPlatform?.call(error, stack) ?? false;
    };
  }

  /// Same contract as [AppLog.runZonedLogged] but also persists zone crashes.
  static Future<void> runZonedLogged(Future<void> Function() body) async {
    await runZonedGuarded(
      body,
      (error, stack) {
        instance.record('Zone', error, stack);
        AppLog.instance.e(
          'Zone',
          'Uncaught async error',
          error: error,
          stackTrace: stack,
        );
      },
    );
  }

  void record(
    String source,
    Object error,
    StackTrace stack, {
    String? message,
  }) {
    final session = LogSession.instance;
    final device = kIsWeb
        ? 'web'
        : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    final msg = message ?? error.toString();
    final ts = DateTime.now().toUtc();

    final block = StringBuffer()
      ..writeln('$_crashStart${ts.toIso8601String()} source=$source =====')
      ..writeln('session=${session.sessionId} ver=${session.appVersion} '
          'platform=${session.platform} device=$device')
      ..writeln('message=$msg')
      ..writeln('stack:')
      ..writeln(stack)
      ..writeln(_crashEnd);

    _appendSync(block.toString());
  }

  /// Most recent [limit] crashes parsed from on-disk files (newest first).
  Future<List<CrashRecord>> recent({int limit = 5}) async {
    if (kIsWeb) return [];
    final files = await _listCrashFiles();
    if (files.isEmpty) return [];

    final records = <CrashRecord>[];
    for (var i = files.length - 1; i >= 0 && records.length < limit * 3; i--) {
      final text = await files[i].readAsString();
      records.addAll(_parseRecords(text));
    }
    records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (records.length <= limit) return records;
    return records.sublist(0, limit);
  }

  /// Builds a temp `.txt` bundle of crash logs for sharing.
  Future<File> buildShareFile() async {
    if (kIsWeb) {
      throw UnsupportedError('Crash export is not available on web');
    }

    final files = await _listCrashFiles();
    final body = StringBuffer()
      ..writeln('===== Media Client crash export =====')
      ..writeln('generated_at=${DateTime.now().toIso8601String()}')
      ..writeln(LogSession.instance.banner())
      ..writeln();

    if (files.isEmpty) {
      body.writeln('(no crash logs on disk)');
    } else {
      for (final f in files) {
        body.writeln('----- ${f.uri.pathSegments.last} -----');
        body.write(await f.readAsString());
        if (!body.toString().endsWith('\n')) body.writeln();
        body.writeln();
      }
    }

    final tempDir = await getTemporaryDirectory();
    final stamp = _shareTimestamp(DateTime.now());
    final out = File(
      '${tempDir.path}${Platform.pathSeparator}media_client_crash_$stamp.txt',
    );
    await out.writeAsString(body.toString());
    return out;
  }

  Future<List<File>> _listCrashFiles() async {
    final dir = _logDir;
    if (dir == null || !await dir.exists()) return [];

    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.startsWith(_filePrefix) && name.endsWith('.log')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  List<CrashRecord> _parseRecords(String text) {
    final records = <CrashRecord>[];
    final starts = <int>[];
    var idx = 0;
    while (true) {
      final at = text.indexOf(_crashStart, idx);
      if (at < 0) break;
      starts.add(at);
      idx = at + _crashStart.length;
    }
    if (starts.isEmpty) return records;

    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      final end = i + 1 < starts.length ? starts[i + 1] : text.length;
      final chunk = text.substring(start, end);
      final parsed = _parseOne(chunk);
      if (parsed != null) records.add(parsed);
    }
    return records;
  }

  CrashRecord? _parseOne(String chunk) {
    final headerEnd = chunk.indexOf('\n');
    if (headerEnd < 0) return null;

    final header = chunk.substring(0, headerEnd);
    // ===== CRASH 2026-05-28T14:30:00.123Z source=FlutterError =====
    final tsMatch = RegExp(r'===== CRASH (\S+) source=(\S+) =====').firstMatch(header);
    if (tsMatch == null) return null;

    final timestamp = DateTime.tryParse(tsMatch.group(1)!);
    final source = tsMatch.group(2)!;
    if (timestamp == null) return null;

    var sessionId = '?';
    var appVersion = '?';
    var platform = '?';
    var device = '?';
    var message = '';
    var stackTrace = '';

    final metaMatch = RegExp(
      r'session=(\S+) ver=(\S+) platform=(\S+) device=(.+)\n',
    ).firstMatch(chunk);
    if (metaMatch != null) {
      sessionId = metaMatch.group(1)!;
      appVersion = metaMatch.group(2)!;
      platform = metaMatch.group(3)!;
      device = metaMatch.group(4)!.trim();
    }

    final msgIdx = chunk.indexOf('message=');
    final stackIdx = chunk.indexOf('stack:\n');
    if (msgIdx >= 0 && stackIdx > msgIdx) {
      message = chunk.substring(msgIdx + 'message='.length, stackIdx).trim();
    }
    final stackEnd = chunk.indexOf(_crashEnd);
    if (stackIdx >= 0) {
      final stackStart = stackIdx + 'stack:\n'.length;
      final stackStop = stackEnd >= 0 ? stackEnd : chunk.length;
      stackTrace = chunk.substring(stackStart, stackStop).trim();
    }

    return CrashRecord(
      timestamp: timestamp,
      source: source,
      sessionId: sessionId,
      appVersion: appVersion,
      platform: platform,
      device: device,
      message: message,
      stackTrace: stackTrace,
    );
  }

  void _appendSync(String text) {
    if (kIsWeb || _logDir == null) return;

    try {
      _rotateIfNeededSync();
      _trimIfOversizedSync();
      _activeCrashFile.writeAsStringSync(text, mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  File get _activeCrashFile {
    final date = _activeDate ?? _dateKey(DateTime.now());
    return File('${_logDir!.path}${Platform.pathSeparator}$_filePrefix$date.log');
  }

  void _rotateIfNeededSync() {
    final dir = _logDir;
    if (dir == null) return;

    final today = _dateKey(DateTime.now());
    if (_activeDate == today) return;
    _activeDate = today;
  }

  void _trimIfOversizedSync() {
    final dir = _logDir;
    final date = _activeDate;
    if (dir == null || date == null) return;

    final file = File('${dir.path}${Platform.pathSeparator}$_filePrefix$date.log');
    if (!file.existsSync()) return;

    final len = file.lengthSync();
    if (len <= _maxFileBytes) return;

    final content = file.readAsStringSync();
    final keepFrom = content.length > _maxFileBytes ~/ 2
        ? content.length - (_maxFileBytes ~/ 2)
        : 0;
    final trimmed = content.substring(keepFrom);
    final notice =
        '===== CRASH LOG TRUNCATED ${DateTime.now().toIso8601String()} '
        '(file exceeded ${_maxFileBytes ~/ 1024}KB) =====\n';
    file.writeAsStringSync('$notice$trimmed', flush: true);
  }

  static String _dateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _shareTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}_${two(dt.hour)}'
        '${two(dt.minute)}${two(dt.second)}';
  }
}
