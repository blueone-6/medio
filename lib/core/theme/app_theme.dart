import 'package:flutter/material.dart';

import 'app_accent_palette.dart';
import 'app_colors.dart';
import 'app_elevation.dart';
import 'app_fonts.dart';
import 'app_motion.dart';
import 'app_neutral_scheme.dart';
import 'app_radius.dart';
import 'app_text.dart';
import 'app_theme_variant.dart';

export 'app_theme_variant.dart';

/// 生成 [ThemeData]，根据 [variant] 和 [brightness] 构建。
class AppTheme {
  AppTheme._();

  static ColorScheme _colorScheme({
    required AppThemeVariant variant,
    required Brightness brightness,
  }) {
    final neutral = AppNeutralScheme.forBrightness(brightness);
    final accent = AppAccentPalette.forVariant(variant, brightness);

    return neutral.copyWith(
      primary: accent.primary,
      onPrimary: accent.onPrimary,
      primaryContainer: accent.primaryContainer,
      onPrimaryContainer: accent.onPrimaryContainer,
      inversePrimary: accent.inversePrimary ?? neutral.inversePrimary,
      surfaceTint: Colors.transparent,
    );
  }

  static ThemeData theme({
    required AppThemeVariant variant,
    required Brightness brightness,
  }) {
    final cs = _colorScheme(variant: variant, brightness: brightness);

    final appColors =
        brightness == Brightness.dark ? AppColors.dark(cs) : AppColors.light(cs);
    final playerColors = PlayerColors.cinema(cs);

    final baseTextTheme = buildAppTextTheme();
    final textTheme = baseTextTheme.apply(
      bodyColor: cs.onSurface,
      displayColor: cs.onSurface,
    );

    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      brightness: brightness,
      fontFamily: AppFonts.latinFamily,
      fontFamilyFallback: AppFonts.fallback,
      scaffoldBackgroundColor: cs.surface,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[appColors, playerColors],
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: AppElevation.level0,
        scrolledUnderElevation: AppElevation.level1,
        centerTitle: false,
        titleTextStyle: AppFonts.apply(textTheme.titleLarge!).copyWith(
          color: cs.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
      cardTheme: CardThemeData(
        color: cs.surfaceContainerHighest,
        elevation: AppElevation.level0,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdR),
      ),
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant,
        thickness: 0.5,
        space: 0.5,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: cs.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: AppRadius.smR),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          animationDuration: AppMotion.base,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return cs.onPrimary.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered)) {
              return cs.onPrimary.withValues(alpha: 0.08);
            }
            return null;
          }),
          textStyle: WidgetStateProperty.all(
            AppFonts.apply(textTheme.labelLarge!).copyWith(letterSpacing: 0.2),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: AppRadius.smR),
          ),
          animationDuration: AppMotion.base,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return cs.primary.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.08);
            }
            return null;
          }),
          textStyle: WidgetStateProperty.all(AppFonts.apply(textTheme.labelLarge!)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: AppRadius.smR),
          ),
          side: WidgetStateProperty.all(BorderSide(color: cs.outlineVariant)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          animationDuration: AppMotion.base,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return cs.primary.withValues(alpha: 0.10);
            }
            if (states.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.06);
            }
            return null;
          }),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cs.surfaceContainerHighest,
        selectedColor: cs.primaryContainer,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillR),
        labelStyle: AppFonts.apply(textTheme.labelMedium!).copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      listTileTheme: ListTileThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdR),
        iconColor: cs.onSurfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surfaceContainerLow,
        elevation: AppElevation.level4,
        modalElevation: AppElevation.level4,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        elevation: AppElevation.level4,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xxlR),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cs.inverseSurface,
        contentTextStyle: AppFonts.apply(textTheme.bodyMedium!).copyWith(
          color: cs.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smR),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: cs.inverseSurface.withValues(alpha: 0.92),
          borderRadius: AppRadius.smR,
        ),
        textStyle: AppFonts.apply(textTheme.bodySmall!).copyWith(
          color: cs.onInverseSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surface,
        indicatorColor: cs.primaryContainer,
        elevation: AppElevation.level1,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AppFonts.apply(textTheme.labelMedium!).copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? cs.onSurface : cs.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: cs.surface,
        indicatorColor: cs.primaryContainer,
        selectedIconTheme: IconThemeData(color: cs.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: cs.primary,
        inactiveTrackColor: cs.surfaceContainerHighest,
        thumbColor: cs.primary,
        overlayColor: cs.primary.withValues(alpha: 0.12),
        trackHeight: 3,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: AppRadius.smR,
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.smR,
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.smR,
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
      ),
    );
  }
}
