import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../utils/user_facing_error.dart';
import 'tv_keyboard_handler.dart';

/// TV 端可聚焦的错误面板（D-Pad 重试）。
class TvErrorPanel extends StatelessWidget {
  const TvErrorPanel({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
    this.autofocusRetry = true,
  });

  final Object? error;
  final VoidCallback? onRetry;
  final bool compact;
  final bool autofocusRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconSize = compact ? 32.0 : 48.0;
    final message = error != null ? userFacingMessage(error!) : '发生未知错误';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: iconSize, color: cs.error),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: compact
                ? Theme.of(context).textTheme.bodyMedium
                : Theme.of(context).textTheme.bodyLarge,
          ),
          if (onRetry != null) ...[
            SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
            FocusTraversalOrder(
              order: const NumericFocusOrder(10),
              child: TvFocusActionButton(
                label: '重试',
                icon: Icons.refresh_rounded,
                autofocus: autofocusRetry,
                onActivate: onRetry!,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
