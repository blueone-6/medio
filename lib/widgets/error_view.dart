import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_spacing.dart';
import '../utils/user_facing_error.dart';

class ErrorView extends StatefulWidget {
  const ErrorView({
    super.key,
    this.error,
    this.message,
    this.title,
    this.hint,
    this.onRetry,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.compact = false,
    this.aligned = true,
    this.section,
  }) : assert(error != null || message != null);

  /// Builds copy from [homeSectionErrorInfo] when [section] is set.
  factory ErrorView.forHomeSection({
    Key? key,
    required Object error,
    required HomeLoadSection section,
    required VoidCallback onRetry,
    VoidCallback? onOpenSettings,
    bool compact = false,
    bool aligned = false,
  }) {
    final info = homeSectionErrorInfo(error, section);
    return ErrorView(
      key: key,
      error: error,
      title: info.title,
      message: info.message,
      hint: info.hint,
      onRetry: onRetry,
      secondaryActionLabel: info.suggestsSettings ? '去设置' : null,
      onSecondaryAction: info.suggestsSettings ? onOpenSettings : null,
      compact: compact,
      aligned: aligned,
      section: section,
    );
  }

  final Object? error;
  final String? message;
  final String? title;
  final String? hint;
  final VoidCallback? onRetry;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool compact;
  final bool aligned;
  final HomeLoadSection? section;

  @override
  State<ErrorView> createState() => _ErrorViewState();
}

class _ErrorViewState extends State<ErrorView> {
  bool _showTechnical = false;
  bool _retryPending = false;

  UserFacingErrorInfo? get _info {
    final error = widget.error;
    if (error == null) return null;
    if (widget.section != null) {
      return homeSectionErrorInfo(error, widget.section!);
    }
    return userFacingErrorInfo(error);
  }

  String get _userMessage {
    if (widget.message != null && widget.message!.trim().isNotEmpty) {
      return widget.message!.trim();
    }
    return _info!.message;
  }

  String? get _resolvedHint {
    if (widget.hint != null && widget.hint!.trim().isNotEmpty) {
      return widget.hint!.trim();
    }
    return _info?.hint;
  }

  String? get _technicalDetail {
    final error = widget.error;
    if (error == null) return null;
    final raw = error.toString().trim();
    if (raw.isEmpty || raw == _userMessage) return null;
    return raw;
  }

  Future<void> _handleRetry() async {
    if (_retryPending || widget.onRetry == null) return;
    setState(() => _retryPending = true);
    widget.onRetry!();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _retryPending = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconSize = widget.compact ? 32.0 : 48.0;
    final technical = _technicalDetail;
    final hint = _resolvedHint;
    final titleStyle = widget.compact
        ? Theme.of(context).textTheme.titleSmall
        : Theme.of(context).textTheme.titleMedium;

    final textAlign = widget.aligned ? TextAlign.center : TextAlign.start;
    final crossAlign =
        widget.aligned ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final wrapAlign =
        widget.aligned ? WrapAlignment.center : WrapAlignment.start;

    final body = Padding(
      padding: EdgeInsets.symmetric(
        vertical: widget.compact ? AppSpacing.md : AppSpacing.xl,
        horizontal: widget.aligned ? (widget.compact ? AppSpacing.md : AppSpacing.xl) : 0,
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: crossAlign,
          children: [
            Icon(Icons.error_outline, size: iconSize, color: cs.error),
            SizedBox(height: widget.compact ? AppSpacing.sm : AppSpacing.md),
            if (widget.title != null) ...[
              SelectableText(
                widget.title!,
                textAlign: textAlign,
                style: titleStyle?.copyWith(color: cs.onSurface),
              ),
              SizedBox(height: widget.compact ? AppSpacing.xs : AppSpacing.sm),
            ],
            SelectableText(
              _userMessage,
              textAlign: textAlign,
              style: widget.compact
                  ? Theme.of(context).textTheme.bodyMedium
                  : Theme.of(context).textTheme.bodyLarge,
            ),
            if (hint != null) ...[
              SizedBox(height: widget.compact ? AppSpacing.xs : AppSpacing.sm),
              SelectableText(
                hint,
                textAlign: textAlign,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
            if (technical != null) ...[
              SizedBox(height: widget.compact ? AppSpacing.xs : AppSpacing.sm),
              TextButton(
                onPressed: () => setState(() => _showTechnical = !_showTechnical),
                child: Text(_showTechnical ? '隐藏详情' : '查看详情'),
              ),
              if (_showTechnical) ...[
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  technical,
                  textAlign: textAlign,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                ),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: technical));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制错误详情')),
                    );
                  },
                  child: const Text('复制详情'),
                ),
              ],
            ],
            if (widget.onRetry != null ||
                (widget.secondaryActionLabel != null && widget.onSecondaryAction != null)) ...[
              SizedBox(height: widget.compact ? AppSpacing.sm : AppSpacing.lg),
              Wrap(
                alignment: wrapAlign,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  if (widget.onRetry != null)
                    widget.compact
                        ? TextButton.icon(
                            onPressed: _retryPending ? null : _handleRetry,
                            icon: _retryPending
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: cs.primary,
                                    ),
                                  )
                                : const Icon(Icons.refresh, size: 18),
                            label: Text(_retryPending ? '重试中…' : '重试'),
                          )
                        : FilledButton.icon(
                            onPressed: _retryPending ? null : _handleRetry,
                            icon: _retryPending
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: cs.onPrimary,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            label: Text(_retryPending ? '重试中…' : '重试'),
                          ),
                  if (widget.secondaryActionLabel != null && widget.onSecondaryAction != null)
                    TextButton(
                      onPressed: widget.onSecondaryAction,
                      child: Text(widget.secondaryActionLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    if (widget.aligned) {
      return Center(child: body);
    }
    return Align(alignment: Alignment.centerLeft, child: body);
  }
}
