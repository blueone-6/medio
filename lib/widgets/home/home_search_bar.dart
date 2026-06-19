import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import 'glass_surface.dart';
import 'home_layout.dart';

/// Home search entry; scrolls with feed (not pinned over content).
class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({super.key, this.onSubmitted});

  final void Function(String query)? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholderColor = cs.onSurfaceVariant;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          HomeLayout.horizontalMargin,
          HomeLayout.searchBarVerticalMargin,
          HomeLayout.horizontalMargin,
          HomeLayout.searchBarVerticalMargin,
        ),
        child: Semantics(
          button: true,
          label: '搜索电影、剧集、演员',
          child: SizedBox(
            height: HomeLayout.searchBarHeight,
            child: GlassSurface(
              borderRadius: AppRadius.pillR,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              useBlur: false,
              onTap: () => context.push('/search'),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      '搜索电影、剧集、演员',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: placeholderColor,
                          ),
                    ),
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
