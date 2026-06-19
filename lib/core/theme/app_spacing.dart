import 'package:flutter/widgets.dart';

/// 统一间距标尺（8pt 体系，含 4 的细分档）。
///
/// 与亮暗主题无关，故为常量类而非 ThemeExtension。
/// 用法：`const SizedBox(height: AppSpacing.lg)` / `EdgeInsets.all(AppSpacing.md)`。
abstract final class AppSpacing {
  /// 2 — 发丝级缝隙（徽章描边内缩等）
  static const double xxs = 2;

  /// 4 — 紧凑元素间距
  static const double xs = 4;

  /// 8 — 基础间距
  static const double sm = 8;

  /// 12 — 卡片内边距 / 中等间距
  static const double md = 12;

  /// 16 — 内容默认间距 / 移动端水平边距
  static const double lg = 16;

  /// 20 — 区块内间距
  static const double xl = 20;

  /// 24 — 桌面水平边距 / 区块间距
  static const double xxl = 24;

  /// 32 — 大区块间距
  static const double xxxl = 32;

  /// 40 — 页面级留白
  static const double huge = 40;

  /// 48 — 超大留白 / TV 安全区
  static const double giant = 48;

  /// 网格默认间隔
  static const double gridGap = 16;

  /// 最小可点击触控目标（Material 规范）
  static const double minTouchTarget = 48;

  /// TV overscan 安全区
  static const double tvSafe = 48;
}

/// 常用 EdgeInsets 快捷构造，避免到处手写。
abstract final class AppInsets {
  static const EdgeInsets allSm = EdgeInsets.all(AppSpacing.sm);
  static const EdgeInsets allMd = EdgeInsets.all(AppSpacing.md);
  static const EdgeInsets allLg = EdgeInsets.all(AppSpacing.lg);
  static const EdgeInsets hLg = EdgeInsets.symmetric(horizontal: AppSpacing.lg);
  static const EdgeInsets hXxl = EdgeInsets.symmetric(horizontal: AppSpacing.xxl);
}
