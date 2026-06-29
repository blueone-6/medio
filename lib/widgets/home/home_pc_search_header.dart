import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import 'home_layout.dart';
import 'home_typography.dart';

/// Sticky top search bar for PC home (`streaming-home-pc-navigation-restored`).
class HomePcSearchHeader extends StatefulWidget {
  const HomePcSearchHeader({
    super.key,
    this.query,
    this.hintText = '搜索电影、剧集、演员...',
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.focusNode,
  });

  /// When non-null, renders as an inline editable search field.
  final String? query;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  @override
  State<HomePcSearchHeader> createState() => _HomePcSearchHeaderState();
}

class _HomePcSearchHeaderState extends State<HomePcSearchHeader> {
  late final TextEditingController _controller;
  var _hovered = false;
  var _focused = false;

  bool get _isInlineSearch => widget.query != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query ?? '');
  }

  @override
  void didUpdateWidget(covariant HomePcSearchHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final query = widget.query;
    if (query != null && query != _controller.text) {
      _controller.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onSubmitted?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          HomeLayout.horizontalMargin,
          AppSpacing.sm,
          HomeLayout.horizontalMargin,
          AppSpacing.sm,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: HomeLayout.pcContentMaxWidth),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: HomeLayout.pcSearchMaxWidth),
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hovered = true),
                  onExit: (_) => setState(() => _hovered = false),
                  child: Material(
                    color: cs.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.pillR,
                      side: BorderSide(
                        color: _focused
                            ? cs.primary.withValues(alpha: 0.55)
                            : cs.outlineVariant.withValues(alpha: 0.45),
                        width: _focused ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _isInlineSearch
                        ? _InlineSearchField(
                            controller: _controller,
                            hintText: widget.hintText,
                            focused: _focused,
                            hovered: _hovered,
                            onFocusChange: (f) => setState(() => _focused = f),
                            onChanged: widget.onChanged,
                            onSubmitted: widget.onSubmitted,
                            onClear: _clear,
                            focusNode: widget.focusNode,
                          )
                        : _SearchEntryButton(
                            hintText: widget.hintText,
                            focused: _focused,
                            hovered: _hovered,
                            onFocusChange: (f) => setState(() => _focused = f),
                            onTap: widget.onTap,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineSearchField extends StatelessWidget {
  const _InlineSearchField({
    required this.controller,
    required this.hintText,
    required this.focused,
    required this.hovered,
    required this.onFocusChange,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.focusNode,
  });

  final TextEditingController controller;
  final String hintText;
  final bool focused;
  final bool hovered;
  final ValueChanged<bool> onFocusChange;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback onClear;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasText = controller.text.isNotEmpty;

    return Focus(
      onFocusChange: onFocusChange,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: hovered || focused ? cs.primary : cs.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                focusNode: focusNode,
                controller: controller,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                textInputAction: TextInputAction.search,
                style: HomeTypography.bodyMd(cs.onSurface),
                cursorColor: cs.primary,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  hintText: hintText,
                  hintStyle: HomeTypography.bodyMd(cs.onSurfaceVariant),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (hasText)
              GestureDetector(
                onTap: onClear,
                child: Tooltip(
                  message: '清空搜索',
                  child: Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.xs),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchEntryButton extends StatelessWidget {
  const _SearchEntryButton({
    required this.hintText,
    required this.focused,
    required this.hovered,
    required this.onFocusChange,
    required this.onTap,
  });

  final String hintText;
  final bool focused;
  final bool hovered;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: '搜索电影、剧集、演员，快捷键 Ctrl+F',
      child: Focus(
        onFocusChange: onFocusChange,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.pillR,
          hoverColor: cs.onSurface.withValues(alpha: 0.06),
          focusColor: cs.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: hovered || focused ? cs.primary : cs.onSurfaceVariant,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  hintText,
                  style: HomeTypography.bodyMd(cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
