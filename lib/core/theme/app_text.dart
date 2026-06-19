import 'package:flutter/material.dart';

import 'app_fonts.dart';
import 'app_typography.dart';

/// 统一字体层级（基于 Material 3 type scale，定制字重与字距）。
///
/// 不指定 `color`，交由 Material 按 `ColorScheme` 应用 onSurface 系列，
/// 从而自动适配亮暗与主题变体。字形使用 [AppFonts]（Be Vietnam Pro + Noto Sans SC）。
TextTheme buildAppTextTheme() {
  const base = TextTheme(
    displayLarge: TextStyle(fontSize: 57, height: 1.12, fontWeight: FontWeight.w400, letterSpacing: -0.25),
    displayMedium: TextStyle(fontSize: 45, height: 1.16, fontWeight: FontWeight.w400),
    displaySmall: TextStyle(fontSize: 36, height: 1.22, fontWeight: FontWeight.w600),
    headlineLarge: TextStyle(fontSize: 32, height: 1.25, fontWeight: FontWeight.w700),
    headlineMedium: TextStyle(fontSize: 28, height: 1.29, fontWeight: FontWeight.w700),
    headlineSmall: TextStyle(fontSize: 24, height: 1.33, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 22, height: 1.27, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, height: 1.50, fontWeight: FontWeight.w600, letterSpacing: 0.15),
    titleSmall: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    bodyLarge: TextStyle(fontSize: 16, height: 1.50, fontWeight: FontWeight.w400, letterSpacing: 0.15),
    bodyMedium: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w400, letterSpacing: 0.25),
    bodySmall: TextStyle(fontSize: 12, height: 1.33, fontWeight: FontWeight.w400, letterSpacing: 0.3),
    labelLarge: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    labelMedium: TextStyle(fontSize: 12, height: 1.33, fontWeight: FontWeight.w600, letterSpacing: 0.4),
    labelSmall: TextStyle(fontSize: 11, height: 1.45, fontWeight: FontWeight.w500, letterSpacing: 0.5),
  );
  return AppFonts.applyToTextTheme(base);
}

/// 便捷取 [TextTheme]。
extension AppTextX on BuildContext {
  TextTheme get text => Theme.of(this).textTheme;
}

/// 媒体专用文字样式（基于 textTheme 派生，统一卡片/徽章/区块标题字形）。
abstract final class AppTextStyles {
  /// 海报卡主标题（剧名/影片名）。
  static TextStyle cardTitle(BuildContext c) =>
      AppTypography.cardTitle(Theme.of(c).colorScheme.onSurface);

  /// 海报卡次级标题（集标题等）。
  static TextStyle cardSubtitle(BuildContext c) =>
      AppTypography.cardSubtitle(Theme.of(c).colorScheme.onSurface);

  /// 海报卡元信息（年份/时长/类型）。
  static TextStyle cardMeta(BuildContext c) =>
      AppTypography.cardMeta(Theme.of(c).colorScheme.onSurfaceVariant);

  /// 角标徽章文字（4K/HDR/DV/Atmos）。
  static TextStyle badge(BuildContext c) =>
      AppTypography.badge(Theme.of(c).colorScheme.onSurface);

  /// 区块标题（"最近播放""相关影视"等）。
  static TextStyle sectionTitle(BuildContext c) =>
      AppTypography.sectionTitle(Theme.of(c).colorScheme.onSurface);

  /// 导航/标签 pill 文字。
  static TextStyle navLabel(BuildContext c, {bool selected = false}) =>
      AppTypography.navLabel(
        Theme.of(c).colorScheme.onSurface,
        selected: selected,
      );
}
