import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/platform_layout.dart';
import '../providers/emby_provider.dart';
import '../providers/home_hub_section_provider.dart';
import '../providers/settings_provider.dart';
import '../services/settings_service.dart';
import '../core/theme/app_spacing.dart';
import '../widgets/settings/desktop_shortcuts_settings_group.dart';
import '../widgets/settings/settings_list_tile.dart';
import '../widgets/tv/tv_keyboard_handler.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.embedded = false});

  /// PC 首页壳层内嵌：无 [Scaffold]/[AppBar]。
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsServiceProvider);

    if (context.isTvUi) {
      return _buildTv(context, ref, settings);
    }
    if (embedded) {
      return _buildSettingsList(context, ref, settings);
    }
    return _buildMobile(context, ref, settings);
  }

  Widget _buildTv(BuildContext context, WidgetRef ref, SettingsService settings) {
    return TvScreenShell(
      title: '设置',
      body: ListView(
        children: [
          TvFocusListTile(
            autofocus: true,
            traversalOrder: 1,
            icon: Icons.dns_outlined,
            title: '服务器配置',
            subtitle: 'Emby',
            onActivate: () => context.push('/settings/servers'),
          ),
          _TvHomeRecentPlayLimitTile(settings: settings, ref: ref, order: 2),
          _TvSubtitleFontSizeTile(settings: settings, order: 3),
          TvFocusListTile(
            traversalOrder: 4,
            icon: Icons.palette_outlined,
            title: '主题设置',
            subtitle:
                '${ref.watch(themeVariantProvider).label} · ${ref.watch(themeBrightnessProvider).label}',
            onActivate: () => context.push('/settings/theme'),
          ),
          TvFocusListTile(
            traversalOrder: 5,
            icon: Icons.bug_report_outlined,
            title: '诊断',
            subtitle: '日志路径 · 启动耗时 · API 调用',
            onActivate: () => context.push('/diagnostics'),
          ),
          TvFocusListTile(
            traversalOrder: 6,
            icon: Icons.info_outline,
            title: '关于',
            onActivate: () => context.push('/about'),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(
    BuildContext context,
    WidgetRef ref,
    SettingsService settings,
  ) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _buildSettingsList(context, ref, settings),
    );
  }

  Widget _buildSettingsList(
    BuildContext context,
    WidgetRef ref,
    SettingsService settings,
  ) {
    return ListView(
      children: [
        SettingsListGroup(
          title: '连接',
          children: [
            SettingsListTile(
              icon: Icons.dns_outlined,
              title: '服务器配置',
              subtitle: 'Emby',
              onTap: () => context.push('/settings/servers'),
            ),
          ],
        ),
        SettingsListGroup(
          title: '播放',
          children: [
            _HomeRecentPlayLimitTile(settings: settings, ref: ref),
            _SubtitleFontSizeTile(settings: settings),
          ],
        ),
        SettingsListGroup(
          title: '外观',
          children: [
            SettingsListTile(
              icon: Icons.palette_outlined,
              title: '主题设置',
              subtitle:
                  '${ref.watch(themeVariantProvider).label} · ${ref.watch(themeBrightnessProvider).label}',
              onTap: () => context.push('/settings/theme'),
            ),
          ],
        ),
        if (isDesktopPlatform) const DesktopShortcutsSettingsGroup(),
        SettingsListGroup(
          title: '其他',
          children: [
            SettingsListTile(
              icon: Icons.bug_report_outlined,
              title: '诊断',
              subtitle: '日志路径 · 启动耗时 · API 调用',
              onTap: () => context.push('/diagnostics'),
            ),
            SettingsListTile(
              icon: Icons.info_outline,
              title: '关于',
              onTap: () => context.push('/about'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _TvHomeRecentPlayLimitTile extends StatefulWidget {
  const _TvHomeRecentPlayLimitTile({
    required this.settings,
    required this.ref,
    required this.order,
  });

  final SettingsService settings;
  final WidgetRef ref;
  final double order;

  @override
  State<_TvHomeRecentPlayLimitTile> createState() =>
      _TvHomeRecentPlayLimitTileState();
}

class _TvHomeRecentPlayLimitTileState extends State<_TvHomeRecentPlayLimitTile> {
  late double _limit;

  @override
  void initState() {
    super.initState();
    _limit = widget.settings.homeRecentPlayLimit.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final max = SettingsService.homeRecentPlayLimitMax.toDouble();
    final min = SettingsService.homeRecentPlayLimitMin.toDouble();

    return TvFocusSlider(
      traversalOrder: widget.order,
      icon: Icons.history,
      label: '首页最近播放条数',
      value: _limit,
      min: min,
      max: max,
      divisions:
          SettingsService.homeRecentPlayLimitMax - SettingsService.homeRecentPlayLimitMin,
      valueLabel: '最多 ${_limit.toInt()} 条（Emby 继续观看接口）',
      onChanged: (v) => setState(() => _limit = v),
      onChangeEnd: (v) async {
        final n = v.round();
        await widget.settings.setHomeRecentPlayLimit(n);
        widget.ref.invalidate(embyResumeProvider);
        widget.ref.invalidate(homeHubSectionProvider('recent'));
        if (mounted) setState(() => _limit = n.toDouble());
      },
    );
  }
}

class _TvSubtitleFontSizeTile extends StatefulWidget {
  const _TvSubtitleFontSizeTile({required this.settings, required this.order});

  final SettingsService settings;
  final double order;

  @override
  State<_TvSubtitleFontSizeTile> createState() =>
      _TvSubtitleFontSizeTileState();
}

class _TvSubtitleFontSizeTileState extends State<_TvSubtitleFontSizeTile> {
  late double _fontSize;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.settings.subtitleFontSize;
  }

  @override
  Widget build(BuildContext context) {
    return TvFocusSlider(
      traversalOrder: widget.order,
      icon: Icons.closed_caption_outlined,
      label: '字幕字号',
      value: _fontSize,
      min: 24,
      max: 72,
      divisions: 24,
      valueLabel: '${_fontSize.toStringAsFixed(0)} px',
      onChanged: (v) => setState(() => _fontSize = v),
      onChangeEnd: (v) async {
        await widget.settings.setSubtitleFontSize(v);
        if (mounted) setState(() => _fontSize = v);
      },
    );
  }
}

class _HomeRecentPlayLimitTile extends StatefulWidget {
  const _HomeRecentPlayLimitTile({required this.settings, required this.ref});

  final SettingsService settings;
  final WidgetRef ref;

  @override
  State<_HomeRecentPlayLimitTile> createState() =>
      _HomeRecentPlayLimitTileState();
}

class _HomeRecentPlayLimitTileState extends State<_HomeRecentPlayLimitTile> {
  late double _limit;

  @override
  void initState() {
    super.initState();
    _limit = widget.settings.homeRecentPlayLimit.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final max = SettingsService.homeRecentPlayLimitMax.toDouble();
    final min = SettingsService.homeRecentPlayLimitMin.toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('首页最近播放条数', style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      '最多 ${_limit.toInt()} 条（Emby 继续观看接口）',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Slider(
            value: _limit,
            min: min,
            max: max,
            divisions: SettingsService.homeRecentPlayLimitMax -
                SettingsService.homeRecentPlayLimitMin,
            label: _limit.toInt().toString(),
            onChanged: (v) => setState(() => _limit = v),
            onChangeEnd: (v) async {
              final n = v.round();
              await widget.settings.setHomeRecentPlayLimit(n);
              widget.ref.invalidate(embyResumeProvider);
              widget.ref.invalidate(homeHubSectionProvider('recent'));
              if (mounted) setState(() => _limit = n.toDouble());
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${min.toInt()}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 12)),
              Text('${max.toInt()}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubtitleFontSizeTile extends StatefulWidget {
  const _SubtitleFontSizeTile({required this.settings});

  final SettingsService settings;

  @override
  State<_SubtitleFontSizeTile> createState() => _SubtitleFontSizeTileState();
}

class _SubtitleFontSizeTileState extends State<_SubtitleFontSizeTile> {
  late double _fontSize;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.settings.subtitleFontSize;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.closed_caption_outlined, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('字幕字号', style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      '${_fontSize.toStringAsFixed(0)} px',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Slider(
            value: _fontSize,
            min: 24,
            max: 72,
            divisions: 24,
            label: _fontSize.toStringAsFixed(0),
            onChanged: (v) {
              setState(() => _fontSize = v);
            },
            onChangeEnd: (v) async {
              await widget.settings.setSubtitleFontSize(v);
              if (mounted) {
                setState(() => _fontSize = v);
              }
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('小',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 12)),
              Text('大',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
