import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/layout/platform_layout.dart';
import '../core/logging/app_log.dart';
import '../widgets/tv/tv_keyboard_handler.dart';
import '../core/logging/crash_reporter.dart';
import '../core/logging/log_session.dart';
import '../core/logging/perf.dart';
import '../core/logging/perf_report.dart';
import '../core/theme/app_colors.dart';

/// Diagnostics screen — shows session info, log file location, recent
/// player bootstrap timings, and an "export report to clipboard" action.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  int _refreshTick = 0;
  Future<List<CrashRecord>>? _crashesFuture;

  @override
  void initState() {
    super.initState();
    _crashesFuture = CrashReporter.instance.recent(limit: 5);
  }

  void _bumpRefresh() {
    setState(() {
      _refreshTick++;
      _crashesFuture = CrashReporter.instance.recent(limit: 5);
    });
  }

  Future<int?> _pickLogShareRange() {
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择分享范围'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('最近 1 天'),
              subtitle: const Text('推荐，体积小'),
              onTap: () => Navigator.pop(ctx, 1),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('全部日志'),
              subtitle: const Text('最多 7 天'),
              onTap: () => Navigator.pop(ctx, 0),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareLogs() async {
    if (kIsWeb) return;
    final maxDays = await _pickLogShareRange();
    if (!mounted || maxDays == null) return;

    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final report = PerfReport.build();
      final file = await AppLog.instance.buildShareBundle(
        perfReport: report,
        maxDays: maxDays == 1 ? 1 : null,
      );
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/plain')],
        subject: 'Media Client diagnostics',
        text: 'Media Client 诊断日志导出',
        sharePositionOrigin: origin,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已打开分享面板')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：$e')),
      );
    }
  }

  Future<void> _shareCrashes() async {
    if (kIsWeb) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final file = await CrashReporter.instance.buildShareFile();
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/plain')],
        subject: 'Media Client crash logs',
        text: 'Media Client 崩溃日志导出',
        sharePositionOrigin: origin,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已打开崩溃日志分享面板')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：$e')),
      );
    }
  }

  Future<void> _copyReport() async {
    final report = PerfReport.build();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('诊断报告已复制到剪贴板')),
    );
  }

  Future<void> _openLogDirectory() async {
    final path = AppLog.instance.logDirectoryPath;
    if (path == null) return;
    if (kIsWeb) return;
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [path]);
      } else {
        // Android: copy path to clipboard instead — file managers vary.
        await Clipboard.setData(ClipboardData(text: path));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('日志路径已复制到剪贴板')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // _refreshTick is read so setState rebuilds when user taps the refresh button.
    // The actual data comes from PerfTracer.recent() / AppLog statics below.
    assert(_refreshTick >= 0);

    final session = LogSession.instance;
    final logPath = AppLog.instance.logDirectoryPath;
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final canOpenLogDir = !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final boots = PerfTracer.recentMatching('player.bootstrap');
    final startupStats = PerfTracer.statsFor('app_startup');
    final firstFrameStats = PerfTracer.statsFor('player_first_frame');
    final apiCalls = PerfTracer.recent()
        .where((r) => r.name.startsWith('http.'))
        .take(20)
        .toList();

    final body = ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (context.isTvUi)
            TvFocusListTile(
              autofocus: true,
              icon: Icons.refresh,
              title: '刷新数据',
              onActivate: _bumpRefresh,
            ),
          const _SectionHeader(title: '会话信息'),
          _kv('Session', session.sessionId),
          _kv('App 版本', session.appVersion),
          _kv('平台', '${session.platform}${kIsWeb ? '' : ' (${Platform.operatingSystemVersion})'}'),
          _kv('启动时间', session.startedAt.toIso8601String()),
          _kv('日志路径', logPath ?? '(未初始化)'),
          if (isMobile)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Android/iOS 日志位于应用私有目录，文件管理器无法直接访问。'
                '请使用下方「分享日志」导出。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          _ActionsRow(
            actions: [
              _ActionButton(
                icon: Icons.copy_all_outlined,
                label: '复制诊断报告',
                onTap: _copyReport,
              ),
              if (!kIsWeb)
                _ActionButton(
                  icon: Icons.share_outlined,
                  label: '分享日志',
                  onTap: _shareLogs,
                ),
              if (canOpenLogDir && logPath != null)
                _ActionButton(
                  icon: Icons.folder_open_outlined,
                  label: '打开目录',
                  onTap: _openLogDirectory,
                ),
              _ActionButton(
                icon: Icons.delete_sweep_outlined,
                label: '清空缓冲',
                onTap: () {
                  PerfTracer.clear();
                  _bumpRefresh();
                },
              ),
            ],
          ),
          const Divider(),
          _SectionHeader(
            title: '启动 / 首帧耗时统计',
            subtitle: '最近 ${startupStats.count.clamp(0, 10)} 次 app_startup · '
                '${firstFrameStats.count.clamp(0, 10)} 次 player_first_frame',
          ),
          _StartupStatsCard(
            startup: startupStats,
            firstFrame: firstFrameStats,
          ),
          const Divider(),
          _SectionHeader(
            title: '最近播放启动（${boots.length}）',
            subtitle: '从点击播放到首帧的完整耗时分解',
          ),
          if (boots.isEmpty)
            const _EmptyTile(text: '尚无播放记录，启动一次播放后回到此页查看')
          else
            ...boots.take(5).map(_buildBootstrapTile),
          const Divider(),
          _SectionHeader(
            title: '最近 HTTP 调用（${apiCalls.length}）',
            subtitle: 'Emby 接口耗时',
          ),
          if (apiCalls.isEmpty)
            const _EmptyTile(text: '尚无 HTTP 记录')
          else
            ..._buildApiList(apiCalls),
          const Divider(),
          const _SectionHeader(
            title: '最近崩溃',
            subtitle: '从 media_client_crash_*.log 读取，最多 5 条',
          ),
          FutureBuilder<List<CrashRecord>>(
            future: _crashesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final crashes = snapshot.data ?? [];
              if (crashes.isEmpty) {
                return const _EmptyTile(text: '尚无崩溃记录');
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton.icon(
                        onPressed: _shareCrashes,
                        icon: const Icon(Icons.share_outlined, size: 18),
                        label: const Text('分享崩溃日志'),
                      ),
                    ),
                  ),
                  ...crashes.map(_buildCrashTile),
                ],
              );
            },
          ),
        ],
      );

    if (context.isTvUi) {
      return TvScreenShell(title: '诊断', body: body);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _bumpRefresh,
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: SelectableText(v, style: const TextStyle(fontFamily: 'monospace'))),
        ],
      ),
    );
  }

  Widget _buildCrashTile(CrashRecord r) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(
          r.preview,
          style: const TextStyle(fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${r.timestamp.toLocal().toIso8601String()} · ${r.source} · sess=${r.sessionId}',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _crashMeta('平台', r.platform),
                _crashMeta('版本', r.appVersion),
                _crashMeta('设备', r.device),
                _crashMeta('Session', r.sessionId),
                const SizedBox(height: 8),
                const Text('堆栈', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                SelectableText(
                  r.stackTrace.isEmpty ? '(无堆栈)' : r.stackTrace,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _crashMeta(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBootstrapTile(PerfRecord r) {
    final color = r.success ? context.appColors.success : context.appColors.danger;
    final firstFrameVia = r.context['first_frame_via']?.toString() ?? '?';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(
                  '${r.durationMs} ms',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text('trace=${r.traceId}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${r.startedAt.toIso8601String()}  first_frame_via=$firstFrameVia',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if (r.errorMessage != null) ...[
              const SizedBox(height: 6),
              Text(r.errorMessage!,
                style: TextStyle(color: context.appColors.danger, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            if (r.stages.isNotEmpty) _StageBars(stages: r.stages, total: r.durationMs),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildApiList(List<PerfRecord> rows) {
    return rows.map((r) {
      final host = r.context['host'] ?? '?';
      final path = r.context['path'] ?? '?';
      final status = r.context['status']?.toString() ?? (r.success ? 'ok' : 'err');
      final method = r.name.split('.').last.toUpperCase();
      final slow = r.durationMs > 1000;
      return ListTile(
        dense: true,
        leading: SizedBox(
          width: 56,
          child: Text(
            '${r.durationMs}ms',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'monospace',
              color: !r.success ? Colors.red : (slow ? Colors.orange : null),
              fontWeight: slow || !r.success ? FontWeight.bold : null,
            ),
          ),
        ),
        title: Text('$method $path', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        subtitle: Text('$host · $status', style: const TextStyle(fontSize: 11)),
      );
    }).toList();
  }
}

class _StartupStatsCard extends StatelessWidget {
  const _StartupStatsCard({
    required this.startup,
    required this.firstFrame,
  });

  final PerfLatencyStats startup;
  final PerfLatencyStats firstFrame;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _metricRow('app_startup', startup),
            const SizedBox(height: 12),
            _metricRow('player_first_frame', firstFrame),
            const SizedBox(height: 8),
            const Text(
              'P50/P90 基于最近 10 次成功记录；重启后从日志文件恢复。',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(String label, PerfLatencyStats stats) {
    final sample = stats.count;
    final p50 = stats.p50Ms;
    final p90 = stats.p90Ms;
    final value = sample == 0
        ? '尚无数据'
        : 'P50 ${p50}ms · P90 ${p90}ms · n=$sample';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: sample == 0 ? Colors.grey : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _EmptyTile extends StatelessWidget {
  const _EmptyTile({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Text(text, style: const TextStyle(color: Colors.grey)),
      );
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({required this.actions});
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Wrap(spacing: 8, runSpacing: 8, children: actions),
      );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(fontSize: 13),
        ),
      );
}

/// Visual breakdown of a bootstrap's stages — a tiny horizontal bar chart.
class _StageBars extends StatelessWidget {
  const _StageBars({required this.stages, required this.total});
  final List<PerfStage> stages;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (total <= 0 || stages.isEmpty) return const SizedBox.shrink();
    final palette = [
      Colors.blue, Colors.teal, Colors.orange, Colors.purple,
      Colors.green, Colors.indigo, Colors.pink, Colors.brown,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(stages.length, (i) {
            final s = stages[i];
            final flex = s.elapsedMs <= 0 ? 1 : s.elapsedMs;
            return Expanded(
              flex: flex,
              child: Tooltip(
                message: '${s.name}: ${s.elapsedMs}ms',
                child: Container(
                  height: 14,
                  color: palette[i % palette.length],
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12, runSpacing: 2,
          children: List.generate(stages.length, (i) {
            final s = stages[i];
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, color: palette[i % palette.length]),
                const SizedBox(width: 4),
                Text('${s.name}: ${s.elapsedMs}ms',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              ],
            );
          }),
        ),
      ],
    );
  }
}
