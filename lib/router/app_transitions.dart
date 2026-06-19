import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_motion.dart';

/// 路由转场工厂（go_router `pageBuilder` 使用）。
abstract final class AppTransitions {
  /// Fade-through：用于顶层/同级切换（淡出旧、淡入新）。
  static Page<T> fadeThrough<T>(GoRouterState state, Widget child) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      transitionDuration: AppMotion.page,
      reverseTransitionDuration: AppMotion.base,
      transitionsBuilder: (context, animation, secondary, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: AppMotion.decelerate),
          child: child,
        );
      },
      child: child,
    );
  }

  /// Shared-axis（水平）：用于前进进入下一层（详情/播放等）。
  /// 新页从右侧轻微滑入 + 淡入，旧页向左轻微位移 + 淡出。
  static Page<T> sharedAxis<T>(GoRouterState state, Widget child) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      transitionDuration: AppMotion.page,
      reverseTransitionDuration: AppMotion.base,
      transitionsBuilder: (context, animation, secondary, child) {
        final enter = CurvedAnimation(parent: animation, curve: AppMotion.standard);
        final exit = CurvedAnimation(parent: secondary, curve: AppMotion.standard);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(enter),
          child: FadeTransition(
            opacity: enter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset.zero,
                end: const Offset(-0.04, 0),
              ).animate(exit),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }

  /// Fade-up：用于全屏沉浸页（播放器）——黑场淡入，避免生硬跳切。
  static Page<T> fadeScale<T>(GoRouterState state, Widget child) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      transitionDuration: AppMotion.base,
      reverseTransitionDuration: AppMotion.base,
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(parent: animation, curve: AppMotion.decelerate);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.02, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
