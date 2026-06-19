import 'package:flutter/material.dart';



import '../config/app_config.dart';
import '../config/app_features.dart';

import '../core/layout/platform_layout.dart';

import '../core/theme/app_spacing.dart';

import '../core/theme/app_typography.dart';

import '../widgets/settings/settings_list_tile.dart';

import '../widgets/tv/tv_keyboard_handler.dart';



class AboutScreen extends StatelessWidget {

  const AboutScreen({super.key});



  static const _description =

      '${AppFeatures.appDescription}\n基于 Flutter、Riverpod、GoRouter、media_kit。';



  @override

  Widget build(BuildContext context) {

    final cs = Theme.of(context).colorScheme;



    if (context.isTvUi) {

      return TvScreenShell(

        title: '关于',

        body: Center(

          child: Text(

            '${AppConfig.appName}\n\n$_description',

            textAlign: TextAlign.center,

            style: Theme.of(context).textTheme.bodyLarge,

          ),

        ),

      );

    }



    return Scaffold(

      appBar: AppBar(title: const Text('关于')),

      body: ListView(

        padding: const EdgeInsets.all(AppSpacing.lg),

        children: [

          const SizedBox(height: AppSpacing.xl),

          Icon(Icons.play_circle_filled_rounded, size: 64, color: cs.primary),

          const SizedBox(height: AppSpacing.lg),

          Text(

            AppConfig.appName,

            textAlign: TextAlign.center,

            style: AppTypography.displayLg(cs.onSurface),

          ),

          const SizedBox(height: AppSpacing.sm),

          Text(

            _description,

            textAlign: TextAlign.center,

            style: AppTypography.cardMeta(cs.onSurfaceVariant),

          ),

          const SizedBox(height: AppSpacing.xxxl),

          DecoratedBox(

            decoration: BoxDecoration(

              color: cs.surfaceContainerLow,

              borderRadius: BorderRadius.circular(12),

              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),

            ),

            child: SettingsListTile(

              icon: Icons.tag_outlined,

              title: '版本',

              subtitle: AppConfig.embyClientVersion,

              showChevron: false,

            ),

          ),

        ],

      ),

    );

  }

}

