import 'log_session.dart';
import 'perf.dart';

/// Builds a human-readable diagnostics report from the [PerfTracer] ring buffer.
///
/// Used by the Settings → 诊断 screen and (later) by an export-to-clipboard
/// action. Format is plain text on purpose — pastes cleanly into bug reports.
abstract final class PerfReport {
  /// Bundle the most-recent player bootstraps + API calls into a single string.
  static String build({
    int maxBootstraps = 5,
    int maxApiCalls = 20,
  }) {
    final buf = StringBuffer();
    final s = LogSession.instance;
    buf
      ..writeln('===== Media Client diagnostics =====')
      ..writeln('generated_at = ${DateTime.now().toIso8601String()}')
      ..writeln('session      = ${s.sessionId}')
      ..writeln('app_version  = ${s.appVersion}')
      ..writeln('platform     = ${s.platform}')
      ..writeln('app_uptime   = ${_fmtDur(DateTime.now().difference(s.startedAt))}')
      ..writeln();

    _writeBootstrapSection(buf, maxBootstraps);
    buf.writeln();
    _writeStartupBaselineSection(buf);
    buf.writeln();
    _writeApiSection(buf, maxApiCalls);
    buf.writeln();
    _writeRawSection(buf);

    return buf.toString();
  }

  static void _writeBootstrapSection(StringBuffer buf, int maxN) {
    final boots = PerfTracer.recentMatching('player.bootstrap').take(maxN).toList();
    buf.writeln('--- Recent player bootstraps (newest first, up to $maxN) ---');
    if (boots.isEmpty) {
      buf.writeln('(none yet)');
      return;
    }
    for (var i = 0; i < boots.length; i++) {
      final r = boots[i];
      buf
        ..writeln('[#${i + 1}] trace=${r.traceId}  started=${r.startedAt.toIso8601String()}')
        ..writeln('       total=${r.durationMs}ms  status=${r.success ? "ok" : "err"}');
      if (r.context.isNotEmpty) {
        buf.writeln('       ctx={${PerfFormat.contextInline(r.context)}}');
      }
      if (r.stages.isNotEmpty) {
        buf.writeln('       stages:');
        for (final st in r.stages) {
          buf.writeln('         · ${st.name.padRight(22)} ${st.elapsedMs} ms');
        }
      }
      if (r.errorMessage != null) {
        buf.writeln('       error=${r.errorMessage}');
      }
    }
  }

  static void _writeStartupBaselineSection(StringBuffer buf) {
    buf.writeln('--- Startup / first-frame latency (newest 10, ok only) ---');
    for (final name in ['app_startup', 'player_first_frame']) {
      final stats = PerfTracer.statsFor(name);
      if (stats.count == 0) {
        buf.writeln('  $name: (none yet)');
        continue;
      }
      buf.writeln(
        '  $name: n=${stats.count}  P50=${stats.p50Ms}ms  P90=${stats.p90Ms}ms',
      );
    }
  }

  static void _writeApiSection(StringBuffer buf, int maxN) {
    final apis = PerfTracer.recent()
        .where((r) => r.name.startsWith('http.'))
        .take(maxN)
        .toList();
    buf.writeln('--- Recent HTTP calls (newest first, up to $maxN) ---');
    if (apis.isEmpty) {
      buf.writeln('(none yet)');
      return;
    }
    for (final r in apis) {
      final ctx = PerfFormat.contextInline(r.context);
      buf.writeln(
        '  ${r.durationMs.toString().padLeft(6)} ms  '
        '${r.success ? "ok " : "ERR"}  ${r.name}  $ctx'
        '${r.errorMessage != null ? "  err=${r.errorMessage}" : ""}',
      );
    }
  }

  static void _writeRawSection(StringBuffer buf) {
    final all = PerfTracer.recent();
    final others = all
        .where((r) => !r.name.startsWith('player.bootstrap') && !r.name.startsWith('http.'))
        .take(40)
        .toList();
    buf.writeln('--- Other perf events (newest first, up to 40) ---');
    if (others.isEmpty) {
      buf.writeln('(none)');
      return;
    }
    for (final r in others) {
      final ctx = r.context.isNotEmpty
          ? '  ctx={${PerfFormat.contextInline(r.context)}}'
          : '';
      buf.writeln(
        '  ${r.durationMs.toString().padLeft(6)} ms  '
        '${r.success ? "ok " : "ERR"}  ${r.name}$ctx'
        '${r.errorMessage != null ? "  err=${r.errorMessage}" : ""}',
      );
    }
  }

  static String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h${m}m${s}s';
    if (m > 0) return '${m}m${s}s';
    return '${s}s';
  }
}
