import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_features.dart';
import '../core/layout/platform_layout.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_radius.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_text.dart';

/// Android home shell: bottom [NavigationBar] + end drawer for secondary destinations.
class HomeAndroidShell extends StatefulWidget {
  const HomeAndroidShell({
    super.key,
    required this.homeTab,
    required this.libraryTab,
    this.initialTabIndex = 0,
    this.hideHomeAppBar = false,
  });

  final Widget homeTab;
  final Widget libraryTab;
  final int initialTabIndex;
  final bool hideHomeAppBar;

  @override
  State<HomeAndroidShell> createState() => _HomeAndroidShellState();
}

class _HomeAndroidShellState extends State<HomeAndroidShell> {
  late int _tabIndex;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Index of the "更多" drawer tab (last position).
  int get _moreTabIndex => 2;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTabIndex.clamp(0, _moreTabIndex - 1);
  }

  String get _appBarTitle {
    if (_tabIndex == 0) return '首页';
    if (_tabIndex == 1) return '媒体库';
    return AppFeatures.appName;
  }

  void _onNavTap(int index) {
    if (index == _moreTabIndex) {
      _scaffoldKey.currentState?.openEndDrawer();
      return;
    }
    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hideHomeBar = widget.hideHomeAppBar && _tabIndex == 0;

    final stackChildren = <Widget>[
      widget.homeTab,
      widget.libraryTab,
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: '首页',
      ),
      const NavigationDestination(
        icon: Icon(Icons.folder_outlined),
        selectedIcon: Icon(Icons.folder_rounded),
        label: '媒体库',
      ),
      const NavigationDestination(
        icon: Icon(Icons.menu_rounded),
        selectedIcon: Icon(Icons.menu_rounded),
        label: '更多',
      ),
    ];

    return Scaffold(
      key: _scaffoldKey,
      appBar: hideHomeBar
          ? null
          : AppBar(
              title: Text(_appBarTitle),
              actions: [
                IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => context.push('/search'),
                ),
              ],
            ),
      endDrawer: _HomeMoreDrawer(
        onClose: () => Navigator.of(context).pop(),
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: stackChildren,
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
          ),
        ),
        child: NavigationBarTheme(
            data: NavigationBarThemeData(
              indicatorColor: cs.primaryContainer.withValues(alpha: 0.35),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return IconThemeData(
                  color: selected
                      ? cs.primary
                      : cs.onSurfaceVariant.withValues(alpha: 0.85),
                );
              }),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return AppTextStyles.navLabel(context, selected: selected).copyWith(
                  color: selected
                      ? cs.primary
                      : cs.onSurfaceVariant.withValues(alpha: 0.85),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                );
              }),
            ),
            child: NavigationBar(
            selectedIndex: _tabIndex.clamp(0, _moreTabIndex - 1),
            onDestinationSelected: _onNavTap,
            backgroundColor: cs.surfaceContainer,
            destinations: destinations,
            ),
          ),
      ),
    );
  }
}

class _HomeMoreDrawer extends StatelessWidget {
  const _HomeMoreDrawer({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  kMobileHorizontalPadding, AppSpacing.xl, kMobileHorizontalPadding, AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: AppRadius.smR,
                    ),
                    child: Icon(Icons.play_circle_filled_rounded, size: 24, color: cs.primary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    AppFeatures.appName,
                    style: AppTextStyles.sectionTitle(context).copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _DrawerTile(
              icon: Icons.settings_outlined,
              label: '设置',
              onTap: () {
                onClose();
                context.push('/settings');
              },
            ),
            _DrawerTile(
              icon: Icons.info_outline_rounded,
              label: '关于',
              onTap: () {
                onClose();
                context.push('/about');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
      minVerticalPadding: 12,
    );
  }
}

/// Shared hub tab bar for home (recent sub-tabs).
class HomeHubTabBar extends StatelessWidget {
  const HomeHubTabBar({
    super.key,
    required this.selectedIndex,
    required this.labels,
    required this.onChanged,
  });

  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _PillTab(
              label: labels[i],
              selected: i == selectedIndex,
              onTap: () => onChanged(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.pillR,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.emphasized,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer.withValues(alpha: 0.6) : Colors.transparent,
            borderRadius: AppRadius.pillR,
            border: selected ? Border.all(color: cs.primary.withValues(alpha: 0.3), width: 1) : null,
          ),
          child: Text(
            label,
            style: AppTextStyles.navLabel(context, selected: selected).copyWith(
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
