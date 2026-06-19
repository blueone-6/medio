import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text.dart';
import 'home_layout.dart';
import 'home_typography.dart';

/// Section header: title left, optional trailing link, bottom-aligned (`items-end`).
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    super.key,
    required this.title,
    this.titleStyle,
    this.trailingStyle,
    this.trailingLabel,
    this.onTrailingTap,
    this.onTitleTap,
    this.trailing,
    this.trailingIcon = Icons.chevron_right,
  });

  final String title;
  final TextStyle? titleStyle;
  final TextStyle? trailingStyle;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;
  final VoidCallback? onTitleTap;
  final Widget? trailing;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolvedTitleStyle = titleStyle ??
        AppTextStyles.sectionTitle(context).copyWith(
          fontSize: HomeLayout.sectionTitleFontSize,
          height: HomeLayout.sectionTitleLineHeight,
          letterSpacing: HomeLayout.sectionTitleLetterSpacing,
          color: cs.onSurface,
        );

    Widget titleWidget = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: resolvedTitleStyle,
    );
    if (onTitleTap != null) {
      titleWidget = GestureDetector(
        onTap: onTitleTap,
        behavior: HitTestBehavior.opaque,
        child: titleWidget,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: titleWidget),
        if (trailing != null)
          trailing!
        else if (trailingLabel != null && onTrailingTap != null)
          _SectionTrailingLink(
            label: trailingLabel!,
            icon: trailingIcon,
            onTap: onTrailingTap!,
            style: trailingStyle,
          ),
      ],
    );
  }
}

class _SectionTrailingLink extends StatefulWidget {
  const _SectionTrailingLink({
    required this.label,
    required this.icon,
    required this.onTap,
    this.style,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final TextStyle? style;

  @override
  State<_SectionTrailingLink> createState() => _SectionTrailingLinkState();
}

class _SectionTrailingLinkState extends State<_SectionTrailingLink> {
  var _hovered = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final linkStyle = widget.style ??
        HomeTypography.sectionTrailingLink(
          cs,
          hovered: _hovered,
          focused: _focused,
        );

    return Semantics(
      button: true,
      label: widget.label,
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: AppRadius.smR,
              hoverColor: cs.onSurface.withValues(alpha: 0.05),
              focusColor: cs.primary.withValues(alpha: 0.08),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.smR,
                  border: _focused
                      ? Border.all(
                          color: cs.primary.withValues(alpha: 0.55),
                          width: 2,
                        )
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.label, style: linkStyle),
                      Icon(widget.icon, size: 18, color: linkStyle.color),
                    ],
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
