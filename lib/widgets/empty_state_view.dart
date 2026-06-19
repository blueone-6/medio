import 'package:flutter/material.dart';

import '../core/theme/app_spacing.dart';
import '../core/theme/app_text.dart';

/// Composed empty state — icon, title, optional subtitle and action.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.centered = true,
    this.autofocusAction = false,
    this.iconColor,
    this.titleStyle,
    this.subtitleStyle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final bool centered;
  final bool autofocusAction;
  final Color? iconColor;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconSize = compact ? 28.0 : 48.0;
    final resolvedIconColor = iconColor ?? cs.onSurfaceVariant.withValues(alpha: compact ? 0.7 : 0.85);
    final resolvedTitleStyle = titleStyle ??
        (compact
            ? AppTextStyles.cardMeta(context).copyWith(color: cs.onSurfaceVariant)
            : context.text.titleSmall!.copyWith(color: cs.onSurface));
    final resolvedSubtitleStyle = subtitleStyle ??
        context.text.bodySmall!.copyWith(color: cs.onSurfaceVariant);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Icon(icon, size: iconSize, color: resolvedIconColor),
        SizedBox(height: compact ? AppSpacing.xs : AppSpacing.md),
        Text(
          title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: resolvedTitleStyle,
        ),
        if (subtitle != null) ...[
          SizedBox(height: compact ? AppSpacing.xxs : AppSpacing.sm),
          Text(
            subtitle!,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: resolvedSubtitleStyle,
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.lg),
          _ActionButton(
            label: actionLabel!,
            onPressed: onAction!,
            compact: compact,
            autofocus: autofocusAction,
          ),
        ],
      ],
    );

    final padded = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 0 : AppSpacing.xl,
        vertical: compact ? AppSpacing.sm : AppSpacing.xl,
      ),
      child: content,
    );

    if (!centered) return padded;
    return Center(child: padded);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    required this.compact,
    required this.autofocus,
  });

  final String label;
  final VoidCallback onPressed;
  final bool compact;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final button = compact
        ? TextButton(onPressed: onPressed, child: Text(label))
        : FilledButton(onPressed: onPressed, child: Text(label));

    if (!autofocus) return button;
    return Focus(autofocus: true, child: button);
  }
}
