import 'package:flutter/material.dart';

import '../../config/app_features.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import 'home_layout.dart';
import 'home_typography.dart';

enum HomePcNavItem {
  home,
  movies,
  series,
  library,
  settings,
}

class HomePcSidebar extends StatelessWidget {
  const HomePcSidebar({
    super.key,
    required this.selected,
    required this.onHome,
    required this.onMovies,
    required this.onSeries,
    required this.onLibrary,
    required this.onSettings,
  });

  final HomePcNavItem selected;
  final VoidCallback onHome;
  final VoidCallback onMovies;
  final VoidCallback onSeries;
  final VoidCallback onLibrary;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: HomeLayout.pcSidebarWidth,
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
              HomeLayout.pcSidebarNavInset,
              HomeLayout.pcSidebarPaddingTop,
              0,
              HomeLayout.pcSidebarPaddingTop,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HomeLayout.pcSidebarBrandInset - HomeLayout.pcSidebarNavInset,
                    0,
                    HomeLayout.pcSidebarBrandInset - HomeLayout.pcSidebarNavInset,
                    HomeLayout.pcSidebarBrandGap,
                  ),
                  child: Text(
                    AppFeatures.appName,
                    style: HomeTypography.headlineMd(cs.primary),
                  ),
                ),
                _NavLink(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: '首页',
                  selected: selected == HomePcNavItem.home,
                  onPressed: onHome,
                ),
                _NavLink(
                  icon: Icons.movie_outlined,
                  selectedIcon: Icons.movie,
                  label: '电影',
                  selected: selected == HomePcNavItem.movies,
                  onPressed: onMovies,
                ),
                _NavLink(
                  icon: Icons.tv_outlined,
                  selectedIcon: Icons.tv,
                  label: '电视剧',
                  selected: selected == HomePcNavItem.series,
                  onPressed: onSeries,
                ),
                _NavLink(
                  icon: Icons.video_library_outlined,
                  selectedIcon: Icons.video_library,
                  label: '媒体库',
                  selected: selected == HomePcNavItem.library,
                  onPressed: onLibrary,
                ),
                const Spacer(),
                _NavLink(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings,
                  label: '设置',
                  selected: selected == HomePcNavItem.settings,
                  onPressed: onSettings,
                  rotateOnHover: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  const _NavLink({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.rotateOnHover = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final bool rotateOnHover;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  var _hovered = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = widget.selected;

    final iconColor = active
        ? cs.primary
        : (_hovered || _focused ? cs.onSurface : cs.onSurfaceVariant);
    final labelStyle = HomeTypography.navLabel(iconColor).copyWith(
      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: HomeLayout.pcSidebarNavGap),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.smR,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: AppRadius.smR,
              hoverColor: cs.onSurface.withValues(alpha: 0.05),
              focusColor: cs.primary.withValues(alpha: 0.08),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: active
                      ? cs.primaryContainer.withValues(alpha: 0.22)
                      : (_hovered ? cs.onSurface.withValues(alpha: 0.05) : null),
                  borderRadius: AppRadius.smR,
                  border: active
                      ? Border.all(color: cs.primary.withValues(alpha: 0.35))
                      : _focused
                          ? Border.all(color: cs.primary.withValues(alpha: 0.55), width: 2)
                          : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HomeLayout.pcSidebarNavPaddingH,
                    HomeLayout.pcSidebarNavPaddingV,
                    HomeLayout.pcSidebarNavPaddingH,
                    HomeLayout.pcSidebarNavPaddingV,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: HomeLayout.pcSidebarIconSize,
                        height: HomeLayout.pcSidebarIconSize,
                        child: Center(
                          child: widget.rotateOnHover
                              ? AnimatedRotation(
                                  turns: _hovered ? 0.25 : 0.0,
                                  duration: AppMotion.effectiveDuration(context, AppMotion.base),
                                  curve: AppMotion.decelerate,
                                  child: Icon(
                                    active ? widget.selectedIcon : widget.icon,
                                    size: HomeLayout.pcSidebarIconSize,
                                    color: iconColor,
                                  ),
                                )
                              : Icon(
                                  active ? widget.selectedIcon : widget.icon,
                                  size: HomeLayout.pcSidebarIconSize,
                                  color: iconColor,
                                ),
                        ),
                      ),
                      const SizedBox(width: HomeLayout.pcSidebarIconGap),
                      Expanded(
                        child: Text(
                          widget.label,
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
          ),
        ),
      ),
    );
  }
}
