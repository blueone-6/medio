import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'log_session.dart';
import 'perf.dart';

/// File + console logging with 7-day retention.
///
/// Public API ([d] / [i] / [w] / [e] / [init] / [installGlobalHandlers] /
/// [runZonedLogged]) is intentionally **unchanged** — every existing call
/// site keeps working.
///
/// Output line shape:
/// ```
/// 2026-05-27T01:12:33.456 [INFO] sess=a3f9 Player | open itemId=123 url=...
/// ```
/// When a [trace] is bound via [bindTrace] or via [perfEvent], the prefix
/// also includes `trace=<id>` and PERF lines append `dur=Xms stages=[...]`.
class AppLog {
  AppLog._();

  static final AppLog instance = AppLog._();

  static const _retentionDays = 7;
  static const retentionDays = _retentionDays;
  static const _filePrefix = 'media_client_';
  static const _shareMaxBytes = 8 * 1024 * 1024;
  static const _shareTruncateDays = 3;

  Directory? _logDir;
  IOSink? _sink;
  String? _activeDate;
  bool _initialized = false;

  /// Current trace id bound by [bindTrace]. Stored per-zone via [Zone].
  static const _traceZoneKey = #AppLog.traceId;

  /// Logs directory once [init] has run, otherwise `null`.
  String? get logDirectoryPath => _logDir?.path;

  /// Read-only snapshot for diagnostics screen ("session=… ver=… platform=…").
  String get sessionBanner => LogSession.instance.banner();

  /// Lists on-disk log files under [logDirectoryPath], oldest first.
  Future<List<File>> listLogFiles() async {
    if (kIsWeb) return [];
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

  /// Merges [perfReport] and log files into a single temp `.txt` for sharing.
  ///
  /// [maxDays]: `null` = all retained files (up to 7 days); `1` = today only.
  /// Flushes the active log sink first. When [maxDays] is null and the bundle
  /// exceeds [_shareMaxBytes], only the most recent [_shareTruncateDays] files
  /// are included.
  Future<File> buildShareBundle({
    required String perfReport,
    int? maxDays,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Log export is not available on web');
    }

    await _sink?.flush();

    final allFiles = await listLogFiles();
    final generatedAt = DateTime.now();
    final logRangeLabel = maxDays == 1
        ? 'last_1_day'
        : 'all (up to $_retentionDays days retention)';
    final logFiles = maxDays == null
        ? allFiles
        : _filterLogFilesByMaxDays(allFiles, maxDays, generatedAt);

    final header = StringBuffer()
      ..writeln('===== Media Client diagnostic export =====')
      ..writeln('NOTE: 可能含有播放 URL，请勿公开分享。')
      ..writeln('generated_at = ${generatedAt.toIso8601String()}')
      ..writeln('log_range = $logRangeLabel')
      ..writeln()
      ..writeln(perfReport)
      ..writeln()
      ..writeln('===== Log files =====')
      ..writeln();

    Future<int> estimateBytes(List<File> files) async {
      var total = header.length;
      for (final f in files) {
        total += await f.length() + 80;
      }
      return total;
    }

    var selectedFiles = logFiles;
    var truncated = false;
    if (maxDays == null &&
        selectedFiles.isNotEmpty &&
        await estimateBytes(selectedFiles) > _shareMaxBytes &&
        selectedFiles.length > _shareTruncateDays) {
      selectedFiles = selectedFiles.sublist(selectedFiles.length - _shareTruncateDays);
      truncated = true;
    }

    final body = StringBuffer();
    if (truncated) {
      body.writeln(
        '(Log section truncated to last $_shareTruncateDays days due to size limit)',
      );
      body.writeln();
    }
    if (selectedFiles.isEmpty) {
      body.writeln('(no log files on disk for selected range)');
    } else {
      for (final f in selectedFiles) {
        body.writeln('----- ${f.uri.pathSegments.last} -----');
        body.write(await f.readAsString());
        if (!body.toString().endsWith('\n')) body.writeln();
        body.writeln();
      }
    }

    final tempDir = await getTemporaryDirectory();
    final stamp = _shareTimestamp(generatedAt);
    final out = File(
      '${tempDir.path}${Platform.pathSeparator}media_client_diag_$stamp.txt',
    );
    await out.writeAsString('$header$body');
    return out;
  }

  static List<File> _filterLogFilesByMaxDays(
    List<File> files,
    int maxDays,
    DateTime now,
  ) {
    if (maxDays <= 0) return files;
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = today.subtract(Duration(days: maxDays - 1));
    return files.where((f) {
      final parsed = _parseLogFileDate(f);
      if (parsed == null) return false;
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      return !day.isBefore(cutoff);
    }).toList();
  }

  static DateTime? _parseLogFileDate(File file) {
    final name = file.uri.pathSegments.last;
    if (!name.startsWith(_filePrefix) || !name.endsWith('.log')) return null;
    final datePart = name.substring(_filePrefix.length, name.length - 4);
    return DateTime.tryParse(datePart);
  }

  static String _shareTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}_${two(dt.hour)}'
        '${two(dt.minute)}${two(dt.second)}';
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) return;

    try {
      final support = await getApplicationSupportDirectory();
      _logDir = Directory('${support.path}${Platform.pathSeparator}logs');
      await _logDir!.create(recursive: true);
      await _purgeExpired();
      await _rotateIfNeeded();
      // Banner first — guarantees every log file starts with diagnostics.
      _writeRaw(
        '===== APP START ${DateTime.now().toIso8601String()} '
        '${LogSession.instance.banner()} =====',
      );
      i('AppLog', 'Logging initialized at ${_logDir!.path}');
    } catch (e, st) {
      _logDir = null;
      debugPrint('AppLog init failed, continuing with console-only logging: $e\n$st');
    }
  }

  void d(String tag, String message, [Object? detail]) =>
      _write('DEBUG', tag, message, detail);

  void i(String tag, String message, [Object? detail]) =>
      _write('INFO', tag, message, detail);

  void w(String tag, String message, [Object? detail]) =>
      _write('WARN', tag, message, detail);

  void e(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final buf = StringBuffer(message);
    if (error != null) buf.write(' | error=$error');
    if (stackTrace != null) buf.write('\n$stackTrace');
    _write('ERROR', tag, buf.toString(), null);
  }

  /// Emit a PERF line for a completed [PerfRecord]. Called by [PerfTracer].
  void perfEvent(PerfRecord r) {
    final ctx = PerfFormat.contextInline(r.context);
    final stages = PerfFormat.stagesInline(r.stages);
    final status = r.success ? 'ok' : 'err';
    final extras = [
      'dur=${r.durationMs}ms',
      'status=$status',
      if (stages.isNotEmpty) stages,
      if (ctx.isNotEmpty) ctx,
      if (r.errorMessage != null) 'err=${_escape(r.errorMessage!)}',
    ].join(' ');
    _writeWithTrace(
      level: 'PERF',
      tag: 'Perf',
      message: r.name,
      detail: extras,
      traceId: r.traceId,
    );
  }

  /// Runs [body] with [traceId] bound, so every log inside the call appends
  /// `trace=<id>` automatically. Used by API interceptor and player bootstrap.
  static Future<T> bindTrace<T>(String traceId, Future<T> Function() body) {
    return runZoned(body, zoneValues: {_traceZoneKey: traceId});
  }

  /// Current trace id (set via [bindTrace]), or `null` if none.
  static String? get currentTraceId => Zone.current[_traceZoneKey] as String?;

  /// Installs Flutter / platform / zone error handlers. Call once from [main].
  static void installGlobalHandlers() {
    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      instance.e(
        'FlutterError',
        details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
      );
      prevFlutter?.call(details);
    };

    final prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      instance.e(
        'PlatformDispatcher',
        error.toString(),
        error: error,
        stackTrace: stack,
      );
      return prevPlatform?.call(error, stack) ?? false;
    };
  }

  /// Runs [body] in a guarded zone. All Flutter binding init and [runApp] must
  /// happen inside this zone (same zone as [WidgetsFlutterBinding.ensureInitialized]).
  static Future<void> runZonedLogged(Future<void> Function() body) async {
    await runZonedGuarded(
      body,
      (error, stack) {
        instance.e(
          'Zone',
          'Uncaught async error',
          error: error,
          stackTrace: stack,
        );
      },
    );
  }

  Future<void> _purgeExpired() async {
    final dir = _logDir;
    if (dir == null || !await dir.exists()) return;

    final cutoff = DateTime.now().subtract(const Duration(days: _retentionDays));
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_filePrefix) || !name.endsWith('.log')) continue;
      final datePart = name.substring(_filePrefix.length, name.length - 4);
      final parsed = DateTime.tryParse(datePart);
      if (parsed != null && parsed.isBefore(cutoff)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _rotateIfNeeded() async {
    final dir = _logDir;
    if (dir == null) return;

    final today = _dateKey(DateTime.now());
    if (_activeDate == today && _sink != null) return;

    await _sink?.flush();
    await _sink?.close();
    _sink = null;

    final file = File('${dir.path}${Platform.pathSeparator}$_filePrefix$today.log');
    _sink = file.openWrite(mode: FileMode.append);
    _activeDate = today;
  }

  void _write(String level, String tag, String message, Object? detail) {
    _writeWithTrace(
      level: level,
      tag: tag,
      message: message,
      detail: detail?.toString(),
      traceId: currentTraceId,
    );
  }

  void _writeWithTrace({
    required String level,
    required String tag,
    required String message,
    String? detail,
    String? traceId,
  }) {
    final sess = LogSession.instance.sessionId;
    final tracePart = traceId == null ? '' : ' trace=$traceId';
    final body = detail == null || detail.isEmpty
        ? '$tag | $message'
        : '$tag | $message | $detail';
    final line = '[$level] sess=$sess$tracePart $body';
    _writeRaw(line);
  }

  void _writeRaw(String line) {
    final stamped = '${DateTime.now().toIso8601String()} $line';
    if (kDebugMode) debugPrint(stamped);

    if (kIsWeb || _logDir == null) return;

    unawaited(() async {
      try {
        await _rotateIfNeeded();
        _sink?.writeln(stamped);
        await _sink?.flush();
      } catch (_) {}
    }());
  }

  static String _escape(String s) {
    // Keep PERF lines greppable: collapse newlines and pipes inside error text.
    return s.replaceAll('\n', ' ').replaceAll('|', '/');
  }

  static String _dateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
