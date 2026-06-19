import 'package:flutter/material.dart';

import '../core/theme/app_spacing.dart';
import 'home/home_section_header.dart';

/// Canonical section header — delegates to [HomeSectionHeader] with standard padding.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.onTitleTap,
    this.onMore,
    this.moreLabel = '更多',
    this.moreIcon = Icons.chevron_right,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.sm,
    ),
  });

  final String title;
  final VoidCallback? onTitleTap;
  final VoidCallback? onMore;
  final String moreLabel;
  final IconData moreIcon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: HomeSectionHeader(
        title: title,
        onTitleTap: onTitleTap,
        trailingLabel: onMore != null ? moreLabel : null,
        onTrailingTap: onMore,
        trailingIcon: moreIcon,
      ),
    );
  }
}
