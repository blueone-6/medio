import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/platform_layout.dart';
import '../core/theme/app_accent_palette.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_text.dart';
import '../core/theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings/settings_list_tile.dart';
import '../widgets/tv/tv_focus_ring.dart';
import '../widgets/tv/tv_keyboard_handler.dart';

/// 主题设置页：配色方案 + 亮度模式选择。
class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context.isTvUi) {
      return _buildTv(context, ref);
    }
    return _buildMobile(context, ref);
  }

  Widget _buildTv(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsServiceProvider);
    final currentVariant = ref.watch(themeVariantProvider);
    final currentBrightness = ref.watch(themeBrightnessProvider);

    final variants = AppThemeVariant.values
        .where((v) => v != AppThemeVariant.system)
        .toList();
    final brightnessOptions = AppThemeBrightness.values;

    return TvScreenShell(
      title: '主题设置',
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '配色方案',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              '仅影响强调色与交互元素；背景色固定，随亮度模式切换。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < variants.length; i++)
                _TvThemeSwatch(
                  variant: variants[i],
                  selected: currentVariant == variants[i],
                  autofocus: i == 0,
                  onActivate: () async {
                    ref.read(themeVariantProvider.notifier).state = variants[i];
                    await settings.setThemeVariant(variants[i]);
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '亮度模式',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (var i = 0; i < brightnessOptions.length; i++)
            TvFocusRadioTile<AppThemeBrightness>(
              value: brightnessOptions[i],
              groupValue: currentBrightness,
              title: brightnessOptions[i].label,
              traversalOrder: 10 + i.toDouble(),
              onSelected: (val) async {
                ref.read(themeBrightnessProvider.notifier).state = val;
                await settings.setThemeBrightness(val);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsServiceProvider);
    final currentVariant = ref.watch(themeVariantProvider);
    final currentBrightness = ref.watch(themeBrightnessProvider);

    final variants = AppThemeVariant.values
        .where((v) => v != AppThemeVariant.system)
        .toList();

    final brightnessOptions = AppThemeBrightness.values;

    return Scaffold(
      appBar: AppBar(title: const Text('主题设置')),
      body: ListView(
        children: [
          SettingsListGroup(
            title: '配色方案',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                child: Text(
                  '仅影响强调色与交互元素；背景色固定，随亮度模式切换。',
                  style: AppTextStyles.cardMeta(context),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: variants.map((v) {
                final selected = currentVariant == v;
                return _ThemeSwatch(
                  variant: v,
                  selected: selected,
                  onTap: () async {
                    ref.read(themeVariantProvider.notifier).state = v;
                    await settings.setThemeVariant(v);
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsListGroup(
            title: '亮度模式',
            children: [
              for (final b in brightnessOptions)
                RadioListTile<AppThemeBrightness>(
                  value: b,
                  groupValue: currentBrightness,
                  title: Text(b.label),
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (val) async {
                    if (val == null) return;
                    ref.read(themeBrightnessProvider.notifier).state = val;
                    await settings.setThemeBrightness(val);
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _TvThemeSwatch extends StatelessWidget {
  const _TvThemeSwatch({
    required this.variant,
    required this.selected,
    required this.onActivate,
    this.autofocus = false,
  });

  final AppThemeVariant variant;
  final bool selected;
  final VoidCallback onActivate;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = AppAccentPalette.forVariant(variant, cs.brightness);
    final previewColor = variant.seedColor ?? accent.primary;

    return TvFocusRing(
      autofocus: autofocus,
      onActivate: onActivate,
      borderRadius: 12,
      scaleFocused: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 88,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: previewColor,
                shape: BoxShape.circle,
                border: variant == AppThemeVariant.pureDark
                    ? Border.all(color: cs.outlineVariant, width: 1.5)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              variant.label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? cs.primary : cs.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.check, size: 14, color: cs.primary),
              ),
          ],
        ),
      ),
    );
  }
}

/// 单个主题色块（选中时显示边框 + 勾）。
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final AppThemeVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = AppAccentPalette.forVariant(variant, cs.brightness);
    final previewColor = variant.seedColor ?? accent.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: previewColor,
                shape: BoxShape.circle,
                border: variant == AppThemeVariant.pureDark
                    ? Border.all(color: cs.outlineVariant, width: 1.5)
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              variant.label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? cs.primary : cs.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.check, size: 14, color: cs.primary),
              ),
          ],
        ),
      ),
    );
  }
}
