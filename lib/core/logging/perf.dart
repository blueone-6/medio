import 'dart:async';
import 'dart:collection';

import 'app_log.dart';

/// One stage marker inside a [PerfSpan].
class PerfStage {
  PerfStage(this.name, this.elapsedMs);
  final String name;
  final int elapsedMs;
}

/// One completed performance record, kept in a ring buffer for reports.
class PerfRecord {
  PerfRecord({
    required this.name,
    required this.durationMs,
    required this.startedAt,
    required this.success,
    required this.stages,
    required this.context,
    required this.traceId,
    this.errorMessage,
  });

  /// Dotted name, e.g. `player.bootstrap`, `emby.getPlaybackInfo`.
  final String name;

  final int durationMs;
  final DateTime startedAt;
  final bool success;
  final List<PerfStage> stages;
  final Map<String, Object?> context;
  final String traceId;
  final String? errorMessage;
}

/// Active in-flight span. Returned by [PerfTracer.start].
///
/// Hot path: only one [DateTime.now] + one [Stopwatch.elapsedMilliseconds]
/// per stage; no allocations beyond the stages list.
class PerfSpan {
  PerfSpan._({
    required this.name,
    required this.traceId,
    required this.context,
    DateTime? startedAt,
  })  : _sw = Stopwatch()..start(),
        startedAt = startedAt ?? DateTime.now();

  final String name;
  final String traceId;
  final Map<String, Object?> context;
  final DateTime startedAt;
  final Stopwatch _sw;
  final List<PerfStage> _stages = [];
  bool _finished = false;
  int _lastStageMs = 0;

  /// Mark an intermediate checkpoint. Stored as **delta** from previous stage
  /// (or span start), so the printed line reads like a flame graph.
  void stage(String name) {
    if (_finished) return;
    final now = _sw.elapsedMilliseconds;
    _stages.add(PerfStage(name, now - _lastStageMs));
    _lastStageMs = now;
  }

  /// Successful completion. Emits a PERF line and pushes to the ring buffer.
  void end({Map<String, Object?>? extraContext}) {
    if (_finished) return;
    _finished = true;
    _sw.stop();
    final ctx = extraContext == null
        ? context
        : {...context, ...extraContext};
    PerfTracer._record(
      PerfRecord(
        name: name,
        durationMs: _sw.elapsedMilliseconds,
        startedAt: startedAt,
        success: true,
        stages: List.unmodifiable(_stages),
        context: Map.unmodifiable(ctx),
        traceId: traceId,
      ),
    );
  }

  /// Failed completion. Same as [end] but tags the record as failure and
  /// includes an error message (truncated).
  void endError(Object error, [StackTrace? st]) {
    if (_finished) return;
    _finished = true;
    _sw.stop();
    final msg = error.toString();
    PerfTracer._record(
      PerfRecord(
        name: name,
        durationMs: _sw.elapsedMilliseconds,
        startedAt: startedAt,
        success: false,
        stages: List.unmodifiable(_stages),
        context: Map.unmodifiable(context),
        traceId: traceId,
        errorMessage: msg.length > 240 ? '${msg.substring(0, 240)}…' : msg,
      ),
    );
    if (st != null) {
      AppLog.instance.d('Perf', 'stack for $name @ $traceId\n$st');
    }
  }
}

/// Aggregated latency percentiles for a named trace.
class PerfLatencyStats {
  const PerfLatencyStats({
    required this.name,
    required this.count,
    this.p50Ms,
    this.p90Ms,
  });

  final String name;
  final int count;
  final int? p50Ms;
  final int? p90Ms;
}

/// Static facade for creating spans and querying recent records.
abstract final class PerfTracer {
  /// Cap on ring buffer size. ~200 * 240 bytes ≈ 50 KB worst case.
  static const int _capacity = 200;
  static const _logFilePrefix = 'media_client_';
  static final RegExp _perfLineRe = RegExp(
    r'^(\S+)\s+\[PERF\]\s+sess=\S+(?:\s+trace=(\S+))?\s+Perf\s+\|\s+([^|]+?)\s+\|\s+'
    r'dur=(\d+)ms\s+status=(ok|err)',
  );

  static final Queue<PerfRecord> _ring = Queue<PerfRecord>();
  static int _traceCounter = 0;
  static bool _hydratedFromLogs = false;

  /// In-flight cold-start span; started in [main], ended on first [HomeScreen] frame.
  static PerfSpan? appStartupSpan;

  /// Open a span. Caller must call [PerfSpan.end] / [PerfSpan.endError].
  static PerfSpan start(
    String name, {
    Map<String, Object?> context = const {},
    String? traceId,
  }) {
    final id = traceId ?? _autoTraceId(name);
    return PerfSpan._(
      name: name,
      traceId: id,
      context: Map<String, Object?>.from(context),
    );
  }

  /// Wraps an async action; logs success / error / duration automatically.
  static Future<T> measure<T>(
    String name,
    Future<T> Function() action, {
    Map<String, Object?> context = const {},
    String? traceId,
  }) async {
    final span = start(name, context: context, traceId: traceId);
    try {
      final result = await action();
      span.end();
      return result;
    } catch (e, st) {
      span.endError(e, st);
      rethrow;
    }
  }

  /// Snapshot the ring buffer (newest first).
  static List<PerfRecord> recent() {
    return _ring.toList().reversed.toList(growable: false);
  }

  /// Clear all recorded events. Used by "reset diagnostics".
  static void clear() => _ring.clear();

  /// Recent records whose `name` starts with [prefix], newest first.
  static List<PerfRecord> recentMatching(String prefix) {
    return recent().where((r) => r.name.startsWith(prefix)).toList();
  }

  /// Recent successful records with exact [name], newest first.
  static List<PerfRecord> recentNamed(String name, {int max = 10}) {
    return recent()
        .where((r) => r.name == name && r.success)
        .take(max)
        .toList(growable: false);
  }

  /// P50/P90 over the newest [maxSamples] successful records for [name].
  static PerfLatencyStats statsFor(String name, {int maxSamples = 10}) {
    final durations = recentNamed(name, max: maxSamples)
        .map((r) => r.durationMs)
        .toList()
      ..sort();
    if (durations.isEmpty) {
      return PerfLatencyStats(name: name, count: 0);
    }
    return PerfLatencyStats(
      name: name,
      count: durations.length,
      p50Ms: _percentile(durations, 0.50),
      p90Ms: _percentile(durations, 0.90),
    );
  }

  /// Ends the active [appStartupSpan] after the home shell is ready.
  static void finishAppStartupAtHome() {
    final span = appStartupSpan;
    if (span == null) return;
    span.stage('home_ready');
    span.end();
    appStartupSpan = null;
  }

  /// Reload recent PERF lines from on-disk logs (no duplicate log writes).
  static Future<void> hydrateFromLogs() async {
    if (_hydratedFromLogs) return;
    _hydratedFromLogs = true;

    final files = await AppLog.instance.listLogFiles();
    if (files.isEmpty) return;

    final imported = <PerfRecord>[];
    for (final file in files) {
      try {
        final text = await file.readAsString();
        for (final line in text.split('\n')) {
          final record = _parsePerfLogLine(line);
          if (record != null) imported.add(record);
        }
      } catch (_) {}
    }

    if (imported.isEmpty) return;
    imported.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    for (final record in imported) {
      _importRecord(record);
    }
  }

  /// Internal: called by [PerfSpan.end] and [PerfSpan.endError].
  static void _record(PerfRecord r) {
    _ring.addLast(r);
    while (_ring.length > _capacity) {
      _ring.removeFirst();
    }
    AppLog.instance.perfEvent(r);
  }

  static String _autoTraceId(String name) {
    _traceCounter++;
    // First dotted prefix becomes the human-readable type tag.
    final dot = name.indexOf('.');
    final type = dot > 0 ? name.substring(0, dot) : name;
    final n = _traceCounter.toRadixString(16).padLeft(4, '0');
    return '$type-$n';
  }

  static int _percentile(List<int> sorted, double p) {
    if (sorted.isEmpty) return 0;
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx.clamp(0, sorted.length - 1)];
  }

  static void _importRecord(PerfRecord r) {
    final existing = _ring.where(
      (e) => e.traceId == r.traceId && e.name == r.name && e.durationMs == r.durationMs,
    );
    if (existing.isNotEmpty) return;
    _ring.addLast(r);
    while (_ring.length > _capacity) {
      _ring.removeFirst();
    }
  }

  static PerfRecord? _parsePerfLogLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.contains('[PERF]')) return null;
    final match = _perfLineRe.firstMatch(trimmed);
    if (match == null) return null;

    final startedAt = DateTime.tryParse(match.group(1)!);
    if (startedAt == null) return null;

    final name = match.group(3)!.trim();
    final traceId = match.group(2) ??
        'import-$name-${startedAt.millisecondsSinceEpoch}';
    final durationMs = int.tryParse(match.group(4)!);
    if (durationMs == null) return null;
    final success = match.group(5) == 'ok';

    return PerfRecord(
      name: name,
      durationMs: durationMs,
      startedAt: startedAt,
      success: success,
      stages: const [],
      context: const {},
      traceId: traceId,
    );
  }

  /// Log file prefix used by [AppLog]; exposed for offline perf tooling.
  static String get logFilePrefix => _logFilePrefix;
}

/// Format helpers used by both the live log line and the report builder.
class PerfFormat {
  static String stagesInline(List<PerfStage> stages) {
    if (stages.isEmpty) return '';
    final parts = stages.map((s) => '${s.name}:${s.elapsedMs}ms').join(', ');
    return 'stages=[$parts]';
  }

  static String contextInline(Map<String, Object?> ctx) {
    if (ctx.isEmpty) return '';
    final parts = ctx.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${_short(e.value)}')
        .join(' ');
    return parts;
  }

  static String _short(Object? v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.length <= 120) return s;
    return '${s.substring(0, 120)}…';
  }
}
