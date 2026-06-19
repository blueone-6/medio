import 'package:flutter/material.dart';

import '../../core/shortcuts/desktop_shortcut_hints.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import 'settings_list_tile.dart';

/// 设置页「键盘快捷键」分组（仅桌面）。
class DesktopShortcutsSettingsGroup extends StatelessWidget {
  const DesktopShortcutsSettingsGroup({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SettingsListGroup(
      title: '键盘快捷键',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text(
            '在 Windows / macOS / Linux 桌面版可用。侧栏与筛选支持 Tab 键聚焦。',
            style: AppTextStyles.cardMeta(context).copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        for (final hint in kDesktopHomeShortcuts)
          SettingsListTile(
            icon: hint.icon,
            title: hint.action,
            subtitle: hint.detail,
            showChevron: false,
            trailing: _ShortcutKeyChip(label: hint.keys),
          ),
      ],
    );
  }
}

class _ShortcutKeyChip extends StatelessWidget {
  const _ShortcutKeyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppRadius.smR,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: AppTextStyles.cardMeta(context).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ),
    );
  }
}
