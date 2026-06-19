import 'package:flutter/material.dart';

/// 统一动效令牌：时长与曲线。
///
/// 命名对齐 Material 3 motion：标准/强调/减速。
abstract final class AppMotion {
  // ---- 时长 ----
  /// 80ms — 极快微反馈（按下态）
  static const Duration instant = Duration(milliseconds: 80);

  /// 120ms — 快速（hover、小状态切换）
  static const Duration fast = Duration(milliseconds: 120);

  /// 200ms — 基础（多数过渡、淡入淡出）
  static const Duration base = Duration(milliseconds: 200);

  /// 300ms — 慢速（展开/收起、滚动吸附）
  static const Duration slow = Duration(milliseconds: 300);

  /// 350ms — 页面转场
  static const Duration page = Duration(milliseconds: 350);

  /// 1200ms — 骨架 shimmer 一个循环
  static const Duration shimmer = Duration(milliseconds: 1200);

  // ---- 曲线 ----
  /// 标准曲线（进入+离开）
  static const Curve standard = Curves.easeInOutCubicEmphasized;

  /// 强调曲线（重要、有存在感的运动）
  static const Curve emphasized = Curves.easeOutCubic;

  /// 减速（元素进入屏幕）
  static const Curve decelerate = Curves.easeOutCubic;

  /// 加速（元素离开屏幕）
  static const Curve accelerate = Curves.easeInCubic;

  /// 系统「减少动态效果」开启时返回 [Duration.zero]。
  static Duration effectiveDuration(BuildContext context, Duration normal) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
  }

  static bool animationsEnabled(BuildContext context) {
    return !MediaQuery.disableAnimationsOf(context);
  }
}
