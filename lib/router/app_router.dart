import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_transitions.dart';
import '../core/layout/platform_layout.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/media_detail_screen.dart';
import '../screens/player_screen.dart';
import '../screens/tv_player_screen.dart';
import '../screens/recent_play_screen.dart';
import '../screens/search_screen.dart';
import '../screens/season_episode_screen.dart';
import '../screens/server_config_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/theme_settings_screen.dart';
import '../screens/about_screen.dart';
import '../screens/diagnostics_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createAppRouter() {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/home',
        // 不用 fadeThrough：TV 上从登录页 go('/home') 时淡入动画偶发不完成，
        // 子树会一直停在 opacity 0，表现为白屏。
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/library/:parentId',
        pageBuilder: (context, state) {
          final id = state.pathParameters['parentId']!;
          final title = state.uri.queryParameters['title'];
          final items = state.uri.queryParameters['items'];
          return AppTransitions.sharedAxis(
            state,
            LibraryScreen(parentId: id, title: title, includeItemTypes: items),
          );
        },
      ),
      GoRoute(
        path: '/item/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return AppTransitions.sharedAxis(state, MediaDetailScreen(itemId: id));
        },
      ),
      GoRoute(
        path: '/item/:id/season/:seasonId',
        builder: (context, state) {
          final seriesId = state.pathParameters['id']!;
          final seasonId = state.pathParameters['seasonId']!;
          final name = state.uri.queryParameters['name'];
          return SeasonEpisodeScreen(
            seriesId: seriesId,
            seasonId: seasonId,
            seasonName: name,
          );
        },
      ),
      GoRoute(
        path: '/player',
        pageBuilder: (context, state) {
          final itemId = state.uri.queryParameters['itemId']!;
          final ticksRaw = state.uri.queryParameters['positionTicks'];
          final hintTicks =
              ticksRaw != null ? int.tryParse(ticksRaw) : null;
          final screen = isAndroidTv
              ? TvPlayerScreen(
                  key: ValueKey('tv-$itemId'),
                  itemId: itemId,
                  hintPositionTicks: hintTicks,
                )
              : PlayerScreen(
                  key: ValueKey(itemId),
                  itemId: itemId,
                  hintPositionTicks: hintTicks,
                );
          // TV: skip fade/scale — the secondary animation squeezes the home
          // route underneath to ~8px during pop and triggers layout overflows.
          if (deviceTypeOf(context) == DeviceType.tv) {
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: screen,
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              transitionsBuilder: (_, __, ___, child) => child,
            );
          }
          return AppTransitions.fadeScale(state, screen);
        },
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) {
          final q = state.uri.queryParameters['q'];
          return SearchScreen(initialQuery: q);
        },
      ),
      GoRoute(
        path: '/recent-play',
        pageBuilder: (context, state) =>
            AppTransitions.sharedAxis(state, const RecentPlayScreen()),
      ),
      // ── Settings / About ──
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/servers',
        builder: (context, state) => const ServerConfigScreen(),
      ),
      GoRoute(
        path: '/settings/theme',
        builder: (context, state) => const ThemeSettingsScreen(),
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: '/diagnostics',
        builder: (context, state) => const DiagnosticsScreen(),
      ),
    ],
  );
}

final goRouterProvider = Provider<GoRouter>((ref) {
  return createAppRouter();
});
