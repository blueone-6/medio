import 'package:flutter/material.dart';

import '../../config/app_features.dart';
import '../home/home_typography.dart';
import 'tv_focus_ring.dart';
import 'tv_home_layout.dart';

enum TvNavItem { home, movies, series, library }

class TvSidebarNav extends StatelessWidget {
  const TvSidebarNav({
    super.key,
    required this.selected,
    required this.onHome,
    required this.onMovies,
    required this.onSeries,
    required this.onLibrary,
    required this.onSearch,
    required this.onSettings,
  });

  final TvNavItem selected;
  final VoidCallback onHome;
  final VoidCallback onMovies;
  final VoidCallback onSeries;
  final VoidCallback onLibrary;
  final VoidCallback onSearch;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: TvHomeLayout.sidebarWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          border: Border(
            right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
        child: SafeArea(
          right: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              TvHomeLayout.sidebarPaddingH,
              TvHomeLayout.sidebarPaddingTop,
              TvHomeLayout.sidebarPaddingH,
              TvHomeLayout.sidebarPaddingTop,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: TvHomeLayout.sidebarBrandGap),
                  child: Text(
                    AppFeatures.appName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HomeTypography.headlineMd(cs.primary),
                  ),
                ),
                _TvNavLink(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: '首页',
                  selected: selected == TvNavItem.home,
                  onActivate: onHome,
                ),
                _TvNavLink(
                  icon: Icons.movie_outlined,
                  selectedIcon: Icons.movie,
                  label: '电影',
                  selected: selected == TvNavItem.movies,
                  onActivate: onMovies,
                ),
                _TvNavLink(
                  icon: Icons.tv_outlined,
                  selectedIcon: Icons.tv,
                  label: '电视剧',
                  selected: selected == TvNavItem.series,
                  onActivate: onSeries,
                ),
                _TvNavLink(
                  icon: Icons.video_library_outlined,
                  selectedIcon: Icons.video_library,
                  label: '媒体库',
                  selected: selected == TvNavItem.library,
                  onActivate: onLibrary,
                ),
                _TvNavLink(
                  icon: Icons.search_outlined,
                  selectedIcon: Icons.search,
                  label: '搜索',
                  selected: false,
                  onActivate: onSearch,
                ),
                const Spacer(),
                _TvNavLink(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings,
                  label: '设置',
                  selected: false,
                  onActivate: onSettings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvNavLink extends StatelessWidget {
  const _TvNavLink({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onActivate,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = selected;
    final iconColor = active ? cs.primary : cs.onSurfaceVariant;
    final labelColor = active ? cs.primary : cs.onSurfaceVariant;
    final labelStyle = HomeTypography.tvNavLabel(
      labelColor,
      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: TvHomeLayout.sidebarNavGap),
      child: TvFocusRing(
        onActivate: onActivate,
        borderRadius: TvHomeLayout.cardRadius,
        scaleFocused: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(TvHomeLayout.cardRadius),
            border: active
                ? Border.all(color: cs.primary.withValues(alpha: 0.35), width: 1)
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TvHomeLayout.navItemPaddingH,
              vertical: TvHomeLayout.navItemPaddingV,
            ),
            child: Row(
              children: [
                Icon(
                  active ? selectedIcon : icon,
                  size: TvHomeLayout.sidebarIconSize,
                  color: iconColor,
                ),
                const SizedBox(width: TvHomeLayout.sidebarIconGap),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
