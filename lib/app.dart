import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'providers/settings_provider.dart';
import 'router/app_router.dart';
import 'widgets/ambient_background.dart';

class MediaClientApp extends ConsumerWidget {
  const MediaClientApp({super.key});

  ThemeMode _themeMode(AppThemeBrightness brightness) {
    switch (brightness) {
      case AppThemeBrightness.light:
        return ThemeMode.light;
      case AppThemeBrightness.dark:
        return ThemeMode.dark;
      case AppThemeBrightness.system:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final variant = ref.watch(themeVariantProvider);
    final brightness = ref.watch(themeBrightnessProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: AppTheme.theme(variant: variant, brightness: Brightness.light),
      darkTheme: AppTheme.theme(variant: variant, brightness: Brightness.dark),
      themeMode: _themeMode(brightness),
      routerConfig: router,
      builder: (context, child) => AmbientBackground(
        enabled: _grainEnabledFor(context),
        child: child ?? const SizedBox.shrink(),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
      ],
    );
  }
}

/// [GoRouter.state] throws before the first route match — use [routeInformationProvider].
bool _grainEnabledFor(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return true;
  final path = router.routeInformationProvider.value.uri.path;
  return !path.startsWith('/player');
}
