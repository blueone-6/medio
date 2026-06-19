import 'package:flutter/material.dart';

import 'tv_home_layout.dart';

/// TV 遥控器友好的输入框：有序焦点遍历 + 聚焦高亮。
class TvTextField extends StatefulWidget {
  const TvTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    this.obscureText = false,
    this.focusNode,
    this.autofocus = false,
    this.traversalOrder = 0,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final bool obscureText;
  final FocusNode? focusNode;
  final bool autofocus;
  final double traversalOrder;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  late final FocusNode _node;
  bool _focused = false;

  bool get _ownsNode => widget.focusNode == null;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final f = _node.hasFocus;
    if (f != _focused) setState(() => _focused = f);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FocusTraversalOrder(
      order: NumericFocusOrder(widget.traversalOrder),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TvHomeLayout.cardRadius),
          border: Border.all(
            color: _focused ? cs.primary : cs.outline.withValues(alpha: 0.5),
            width: _focused ? 3 : 1,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    blurRadius: TvHomeLayout.focusGlowBlur / 2,
                  ),
                ]
              : const [],
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _node,
          autofocus: widget.autofocus,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          style: textTheme.titleMedium,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            labelStyle: textTheme.titleSmall,
            hintStyle: textTheme.bodyLarge?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
