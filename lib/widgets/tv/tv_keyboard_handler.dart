import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/platform_layout.dart';
import '../../core/theme/app_motion.dart';
import '../../core/tv/tv_remote_actions.dart';
import 'tv_focus_ring.dart';
import 'tv_home_layout.dart';

/// TV 屏幕脚手架：焦点遍历 + BACK 键 + 长按方向键重复滚动。
class TvScreenShell extends StatelessWidget {
  const TvScreenShell({
    super.key,
    this.title,
    required this.body,
    this.onBack,
    this.padding,
  });

  final String? title;
  final Widget body;
  final VoidCallback? onBack;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    void handleBack() {
      if (onBack != null) {
        onBack!();
      } else if (context.canPop()) {
        context.pop();
      }
    }

    return TvRemoteActions(
      onBack: handleBack,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          minimum: const EdgeInsets.all(kTvSafeArea),
          child: TvKeyboardHandler(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                  ],
                  Expanded(
                    child: padding == null
                        ? body
                        : Padding(padding: padding!, child: body),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// D-Pad 可聚焦的设置列表项。
class TvFocusListTile extends StatefulWidget {
  const TvFocusListTile({
    super.key,
    required this.title,
    required this.onActivate,
    this.subtitle,
    this.icon,
    this.trailing,
    this.autofocus = false,
    this.traversalOrder,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback onActivate;
  final bool autofocus;
  final double? traversalOrder;

  @override
  State<TvFocusListTile> createState() => _TvFocusListTileState();
}

class _TvFocusListTileState extends State<TvFocusListTile> {
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!TvRemoteSelectKeys.isSelect(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    widget.onActivate();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget tile = Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.emphasized,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(TvHomeLayout.cardRadius),
              border: Border.all(
                color: focused ? cs.primary : Colors.transparent,
                width: TvHomeLayout.focusBorderWidth,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 24, color: cs.onSurfaceVariant),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: textTheme.titleMedium),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle!,
                            style: textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 8),
                    widget.trailing!,
                  ] else
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (widget.traversalOrder != null) {
      tile = FocusTraversalOrder(
        order: NumericFocusOrder(widget.traversalOrder!),
        child: tile,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: tile,
    );
  }
}

/// TV 图标按钮（播放器控制条、详情页工具栏等）。
class TvFocusIconButton extends StatelessWidget {
  const TvFocusIconButton({
    super.key,
    this.icon,
    this.label,
    required this.onActivate,
    this.enabled = true,
    this.color,
    this.size = 40,
    this.iconSize = 22,
    this.filled = false,
    this.fillColor,
    this.borderRadius = 12,
    this.autofocus = false,
    this.onFocusChange,
  });

  final IconData? icon;
  final String? label;
  final VoidCallback? onActivate;
  final bool enabled;
  final Color? color;
  final double size;
  final double iconSize;
  final bool filled;
  final Color? fillColor;
  final double borderRadius;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurface;
    final child = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: filled
          ? BoxDecoration(
              color: fillColor ?? Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(borderRadius),
            )
          : null,
      child: label != null
          ? Text(
              label!,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            )
          : Icon(icon, color: fg, size: iconSize),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: TvFocusRing(
        autofocus: autofocus,
        onActivate: enabled ? onActivate : null,
        onFocusChange: onFocusChange,
        borderRadius: borderRadius,
        scaleFocused: true,
        child: child,
      ),
    );
  }
}

/// TV 详情页播放按钮：小尺寸、无图标，聚焦时背景色反转（不放大）。
class TvDetailPlayButton extends StatefulWidget {
  const TvDetailPlayButton({
    super.key,
    required this.onActivate,
    this.autofocus = false,
    this.traversalOrder,
    this.onFocusChange,
  });

  final VoidCallback onActivate;
  final bool autofocus;
  final double? traversalOrder;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<TvDetailPlayButton> createState() => _TvDetailPlayButtonState();
}

class _TvDetailPlayButtonState extends State<TvDetailPlayButton> {
  bool _focused = false;

  void _onFocusChange(bool focused) {
    if (_focused != focused) {
      setState(() => _focused = focused);
    }
    widget.onFocusChange?.call(focused);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = _focused ? cs.primary : cs.onPrimary;
    final fg = _focused ? cs.onPrimary : cs.primary;

    Widget btn = TvFocusRing(
      autofocus: widget.autofocus,
      onActivate: widget.onActivate,
      onFocusChange: _onFocusChange,
      borderRadius: 8,
      scaleFocused: false,
      showBorder: false,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.emphasized,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: cs.primary.withValues(alpha: _focused ? 1 : 0.85),
            width: 1.5,
          ),
        ),
        child: Text(
          '播放',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
        ),
      ),
    );

    if (widget.traversalOrder != null) {
      btn = FocusTraversalOrder(
        order: NumericFocusOrder(widget.traversalOrder!),
        child: btn,
      );
    }
    return btn;
  }
}

/// TV 文字操作按钮（播放、选集等药丸按钮）。
class TvFocusActionButton extends StatelessWidget {
  const TvFocusActionButton({
    super.key,
    required this.label,
    required this.onActivate,
    this.icon,
    this.autofocus = false,
    this.filled = true,
    this.compact = false,
    this.traversalOrder,
    this.onFocusChange,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onActivate;
  final bool autofocus;
  final bool filled;
  final bool compact;
  final double? traversalOrder;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget btn = TvFocusRing(
      autofocus: autofocus,
      onActivate: onActivate,
      onFocusChange: onFocusChange,
      borderRadius: TvHomeLayout.cardRadius,
      child: Material(
        color: filled ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(TvHomeLayout.cardRadius),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18,
            vertical: compact ? 8 : 12,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: compact ? 18 : 20,
                  color: filled ? cs.onPrimary : cs.onSurface,
                ),
                SizedBox(width: compact ? 6 : 8),
              ],
              Text(
                label,
                style: (compact ? textTheme.labelLarge : textTheme.titleSmall)?.copyWith(
                  color: filled ? cs.onPrimary : cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (traversalOrder != null) {
      btn = FocusTraversalOrder(
        order: NumericFocusOrder(traversalOrder!),
        child: btn,
      );
    }
    return btn;
  }
}

/// TV 遥控器友好的单选行。
class TvFocusRadioTile<T> extends StatelessWidget {
  const TvFocusRadioTile({
    super.key,
    required this.value,
    required this.groupValue,
    required this.title,
    required this.onSelected,
    this.traversalOrder,
  });

  final T value;
  final T groupValue;
  final String title;
  final ValueChanged<T> onSelected;
  final double? traversalOrder;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final cs = Theme.of(context).colorScheme;

    Widget tile = TvFocusRing(
      onActivate: () => onSelected(value),
      borderRadius: TvHomeLayout.cardRadius,
      scaleFocused: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer.withValues(alpha: 0.25)
              : cs.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(TvHomeLayout.cardRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
        ),
      ),
    );

    if (traversalOrder != null) {
      tile = FocusTraversalOrder(
        order: NumericFocusOrder(traversalOrder!),
        child: tile,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: tile,
    );
  }
}

/// TV 滑块：左右方向键调节，OK 不触发导航。
class TvFocusSlider extends StatefulWidget {
  const TvFocusSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
    required this.onChangeEnd,
    this.icon,
    this.traversalOrder,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final IconData? icon;
  final double? traversalOrder;

  @override
  State<TvFocusSlider> createState() => _TvFocusSliderState();
}

class _TvFocusSliderState extends State<TvFocusSlider> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(TvFocusSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _value = widget.value;
  }

  void _step(double delta) {
    final step = (widget.max - widget.min) / widget.divisions;
    final next = (_value + delta * step).clamp(widget.min, widget.max);
    setState(() => _value = next);
    widget.onChanged(next);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        widget.onChangeEnd(_value);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _step(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget block = Focus(
      onKeyEvent: _onKey,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(TvHomeLayout.cardRadius),
              border: Border.all(
                color: focused ? cs.primary : Colors.transparent,
                width: TvHomeLayout.focusBorderWidth,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 22),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.label, style: textTheme.titleMedium),
                          Text(
                            widget.valueLabel,
                            style: textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Slider(
                  value: _value,
                  min: widget.min,
                  max: widget.max,
                  divisions: widget.divisions,
                  label: widget.valueLabel,
                  onChanged: (v) {
                    setState(() => _value = v);
                    widget.onChanged(v);
                  },
                  onChangeEnd: widget.onChangeEnd,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.min.toInt().toString(),
                      style: TextStyle(color: cs.outline, fontSize: 12),
                    ),
                    Text(
                      '← → 调节',
                      style: TextStyle(color: cs.outline, fontSize: 12),
                    ),
                    Text(
                      widget.max.toInt().toString(),
                      style: TextStyle(color: cs.outline, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    if (widget.traversalOrder != null) {
      block = FocusTraversalOrder(
        order: NumericFocusOrder(widget.traversalOrder!),
        child: block,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: block,
    );
  }
}

/// 长按方向键时对当前焦点附近的可滚动区域做重复滚动（🟡 提升线）。
class TvKeyboardHandler extends StatefulWidget {
  const TvKeyboardHandler({
    super.key,
    required this.child,
    this.repeatScrollStep = 72,
    this.repeatInterval = const Duration(milliseconds: 80),
  });

  final Widget child;
  final double repeatScrollStep;
  final Duration repeatInterval;

  @override
  State<TvKeyboardHandler> createState() => _TvKeyboardHandlerState();
}

class _TvKeyboardHandlerState extends State<TvKeyboardHandler> {
  Timer? _repeatTimer;
  LogicalKeyboardKey? _repeatKey;

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _repeatKey = null;
  }

  void _scroll(LogicalKeyboardKey key, {bool animate = true}) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return;

    ScrollableState? scrollable;
    focused.visitAncestorElements((element) {
      final state = element.findAncestorStateOfType<ScrollableState>();
      if (state != null) {
        scrollable = state;
        return false;
      }
      return true;
    });

    final position = scrollable?.position;
    if (position == null) return;

    final axis = position.axis;
    double delta = widget.repeatScrollStep;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      delta = -delta;
    }

    final target = (axis == Axis.vertical
            ? position.pixels + delta
            : position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);

    if (animate) {
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    } else {
      position.jumpTo(target);
    }
  }

  void _startRepeat(LogicalKeyboardKey key) {
    if (_repeatKey == key) return;
    _stopRepeat();
    _repeatKey = key;
    _scroll(key);
    _repeatTimer = Timer.periodic(widget.repeatInterval, (_) {
      if (!mounted) return;
      _scroll(key, animate: false);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyRepeatEvent) {
      if (TvRemoteArrowKeys.isArrow(event.logicalKey)) {
        _startRepeat(event.logicalKey);
        return KeyEventResult.handled;
      }
    }
    if (event is KeyUpEvent) {
      if (event.logicalKey == _repeatKey) {
        _stopRepeat();
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}
