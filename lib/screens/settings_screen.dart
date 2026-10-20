import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/platform_layout.dart';
import '../providers/emby_provider.dart';
import '../providers/home_hub_section_provider.dart';
import '../providers/home_recommendation_provider.dart';
import '../providers/settings_provider.dart';
import '../services/settings_service.dart';
import '../startup/netdisk_cache_setup.dart';
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
          _TvRecentAddedWindowTile(settings: settings, ref: ref, order: 3),
          _TvSubtitleFontSizeTile(settings: settings, order: 4),
          _TvNetdiskCacheTile(
            settings: settings,
            type: context.deviceType,
            order: 4.5,
          ),
          TvFocusListTile(
            traversalOrder: 5,
            icon: Icons.palette_outlined,
            title: '主题设置',
            subtitle:
                '${ref.watch(themeVariantProvider).label} · ${ref.watch(themeBrightnessProvider).label}',
            onActivate: () => context.push('/settings/theme'),
          ),
          TvFocusListTile(
            traversalOrder: 6,
            icon: Icons.bug_report_outlined,
            title: '诊断',
            subtitle: '日志路径 · 启动耗时 · API 调用',
            onActivate: () => context.push('/diagnostics'),
          ),
          TvFocusListTile(
            traversalOrder: 7,
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
            _RecentAddedWindowTile(settings: settings, ref: ref),
            _SubtitleFontSizeTile(settings: settings),
            _NetdiskCacheTile(settings: settings, type: context.deviceType),
            if (isWindowsPlatform) ...[
              _AudioPassthroughTile(settings: settings),
              _DolbyVisionLibplaceboTile(settings: settings),
            ],
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

class _TvRecentAddedWindowTile extends StatefulWidget {
  const _TvRecentAddedWindowTile({
    required this.settings,
    required this.ref,
    required this.order,
  });

  final SettingsService settings;
  final WidgetRef ref;
  final double order;

  @override
  State<_TvRecentAddedWindowTile> createState() =>
      _TvRecentAddedWindowTileState();
}

class _TvRecentAddedWindowTileState extends State<_TvRecentAddedWindowTile> {
  late double _days;

  @override
  void initState() {
    super.initState();
    _days = widget.settings.recentAddedWindowDays.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final max = SettingsService.recentAddedWindowDaysMax.toDouble();
    final min = SettingsService.recentAddedWindowDaysMin.toDouble();

    return TvFocusSlider(
      traversalOrder: widget.order,
      icon: Icons.new_releases_outlined,
      label: '最近入库天数',
      value: _days,
      min: min,
      max: max,
      divisions:
          SettingsService.recentAddedWindowDaysMax - SettingsService.recentAddedWindowDaysMin,
      valueLabel: '推荐优先展示 ${_days.toInt()} 天内入库的媒体',
      onChanged: (v) => setState(() => _days = v),
      onChangeEnd: (v) async {
        final n = v.round();
        await widget.settings.setRecentAddedWindowDays(n);
        widget.ref.invalidate(homeRecommendationProvider);
        if (mounted) setState(() => _days = n.toDouble());
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
      min: 12,
      max: 72,
      divisions: 30,
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

class _RecentAddedWindowTile extends StatefulWidget {
  const _RecentAddedWindowTile({required this.settings, required this.ref});

  final SettingsService settings;
  final WidgetRef ref;

  @override
  State<_RecentAddedWindowTile> createState() => _RecentAddedWindowTileState();
}

class _RecentAddedWindowTileState extends State<_RecentAddedWindowTile> {
  late double _days;

  @override
  void initState() {
    super.initState();
    _days = widget.settings.recentAddedWindowDays.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final max = SettingsService.recentAddedWindowDaysMax.toDouble();
    final min = SettingsService.recentAddedWindowDaysMin.toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.new_releases_outlined, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('最近入库天数', style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      '推荐优先展示 ${_days.toInt()} 天内入库的媒体',
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
            value: _days,
            min: min,
            max: max,
            divisions: SettingsService.recentAddedWindowDaysMax -
                SettingsService.recentAddedWindowDaysMin,
            label: _days.toInt().toString(),
            onChanged: (v) => setState(() => _days = v),
            onChangeEnd: (v) async {
              final n = v.round();
              await widget.settings.setRecentAddedWindowDays(n);
              widget.ref.invalidate(homeRecommendationProvider);
              if (mounted) setState(() => _days = n.toDouble());
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
            min: 12,
            max: 72,
            divisions: 30,
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

/// Windows 音频直通（Atmos / DTS:X）开关。
///
/// 开启后 mpv 用 WASAPI 独占 + `audio-spdif` 把 TrueHD/EAC3/DTS 源码送到
/// HDMI 上的 AVR/回音壁；需要把功放/回音壁设为系统默认输出。开启期间其他
/// 应用可能没有声音（独占设备）。
class _AudioPassthroughTile extends StatefulWidget {
  const _AudioPassthroughTile({required this.settings});

  final SettingsService settings;

  @override
  State<_AudioPassthroughTile> createState() => _AudioPassthroughTileState();
}

class _AudioPassthroughTileState extends State<_AudioPassthroughTile> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings.audioPassthrough;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(Icons.surround_sound_outlined,
              size: 22, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '音频直通（Atmos / DTS:X）',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  _enabled
                      ? '已开启：源码送到功放，需把 HDMI 功放设为系统默认输出'
                      : '关闭：在本机解码为 PCM（不支持 Atmos 对象声）',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Switch(
            value: _enabled,
            onChanged: (v) async {
              setState(() => _enabled = v);
              await widget.settings.setAudioPassthrough(v);
            },
          ),
        ],
      ),
    );
  }
}

/// Windows Dolby Vision P5 兼容渲染（FFmpeg libplacebo）。
///
/// 当前 media_kit 的 Windows 纹理路径不处理 DV RPU，P5 会发紫/发绿。
/// 开启后把 FFmpeg `libplacebo` 滤镜挂到 mpv 的 vf 链上，先应用 RPU 并
/// tone-map 到 BT.709，再交给现有渲染器。关闭只剥离 DV 元数据，P5 仍偏色。
class _DolbyVisionLibplaceboTile extends StatefulWidget {
  const _DolbyVisionLibplaceboTile({required this.settings});

  final SettingsService settings;

  @override
  State<_DolbyVisionLibplaceboTile> createState() =>
      _DolbyVisionLibplaceboTileState();
}

class _DolbyVisionLibplaceboTileState
    extends State<_DolbyVisionLibplaceboTile> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings.dolbyVisionLibplacebo;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(Icons.hdr_on_outlined, size: 22, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '杜比视界 P5 兼容渲染',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  _enabled
                      ? '已开启：libplacebo 处理 DV 元数据并转 SDR（4K 下略吃 GPU）'
                      : '已关闭：只剥离 DV 元数据，P5 仍会偏紫/偏绿',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Switch(
            value: _enabled,
            onChanged: (v) async {
              setState(() => _enabled = v);
              await widget.settings.setDolbyVisionLibplacebo(v);
            },
          ),
        ],
      ),
    );
  }
}

/// 网盘播放磁盘块缓存设置（手机 / 平板 / 嵌入式）。
class _NetdiskCacheTile extends StatefulWidget {
  const _NetdiskCacheTile({required this.settings, required this.type});

  final SettingsService settings;
  final DeviceType type;

  @override
  State<_NetdiskCacheTile> createState() => _NetdiskCacheTileState();
}

class _NetdiskCacheTileState extends State<_NetdiskCacheTile> {
  late bool _enabled;
  late double _limit;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings.netdiskCacheEnabledFor(widget.type);
    _limit = widget.settings.netdiskCacheLimitMbFor(widget.type).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sd_storage_outlined,
                  size: 22, color: cs.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('网盘播放缓存',
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      _enabled ? '已开启 · 上限 ${_limit.toInt()} MB' : '已关闭（不写入磁盘）',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _enabled,
                onChanged: (v) async {
                  setState(() => _enabled = v);
                  await widget.settings.setNetdiskCacheEnabled(v);
                  await configureNetdiskCache(widget.settings, widget.type);
                },
              ),
            ],
          ),
          if (_enabled) ...[
            const SizedBox(height: AppSpacing.sm),
            Slider(
              value: _limit.clamp(256, 20480),
              min: 256,
              max: 20480,
              divisions: 79,
              label: '${_limit.toInt()} MB',
              onChanged: (v) => setState(() => _limit = v),
              onChangeEnd: (v) async {
                final n = v.round();
                await widget.settings.setNetdiskCacheLimitMb(n);
                await configureNetdiskCache(widget.settings, widget.type);
                if (mounted) setState(() => _limit = n.toDouble());
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// 网盘播放磁盘块缓存设置（TV / D-Pad）。
class _TvNetdiskCacheTile extends StatefulWidget {
  const _TvNetdiskCacheTile({
    required this.settings,
    required this.type,
    required this.order,
  });

  final SettingsService settings;
  final DeviceType type;
  final double order;

  @override
  State<_TvNetdiskCacheTile> createState() => _TvNetdiskCacheTileState();
}

class _TvNetdiskCacheTileState extends State<_TvNetdiskCacheTile> {
  late bool _enabled;
  late double _limit;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings.netdiskCacheEnabledFor(widget.type);
    _limit = widget.settings.netdiskCacheLimitMbFor(widget.type).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TvFocusListTile(
          traversalOrder: widget.order,
          icon: Icons.sd_storage_outlined,
          title: '网盘播放缓存',
          subtitle: _enabled ? '已开启 · 上限 ${_limit.toInt()} MB' : '已关闭（不写入磁盘）',
          onActivate: () async {
            setState(() => _enabled = !_enabled);
            await widget.settings.setNetdiskCacheEnabled(_enabled);
            await configureNetdiskCache(widget.settings, widget.type);
          },
        ),
        if (_enabled)
          TvFocusSlider(
            traversalOrder: widget.order + 0.01,
            icon: Icons.sd_storage_outlined,
            label: '缓存上限',
            value: _limit.clamp(256, 20480),
            min: 256,
            max: 20480,
            divisions: 79,
            valueLabel: '${_limit.toInt()} MB',
            onChanged: (v) => setState(() => _limit = v),
            onChangeEnd: (v) async {
              final n = v.round();
              await widget.settings.setNetdiskCacheLimitMb(n);
              await configureNetdiskCache(widget.settings, widget.type);
              if (mounted) setState(() => _limit = n.toDouble());
            },
          ),
      ],
    );
  }
}
