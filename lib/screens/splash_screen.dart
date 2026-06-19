import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../core/theme/app_typography.dart';
import '../providers/emby_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/loading_indicator.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    final settings = ref.read(settingsServiceProvider);
    final token = settings.embyAccessToken;
    if (token != null && token.isNotEmpty) {
      unawaited(ref.read(embyLibrariesProvider.future));
      unawaited(ref.read(embyResumeProvider.future));
      context.go('/home');
    } else {
      context.go('/settings/servers');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.35),
            radius: 1.2,
            colors: [
              cs.primary.withValues(alpha: 0.12),
              cs.surface,
              cs.surfaceContainerLowest,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_circle_fill, size: 72, color: cs.primary),
              const SizedBox(height: 20),
              Text(
                AppConfig.appName,
                style: AppTypography.displayLg(cs.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '跨平台私人影院客户端',
                style: AppTypography.cardMeta(cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              const LoadingIndicator(message: '正在启动…'),
            ],
          ),
        ),
      ),
    );
  }
}
