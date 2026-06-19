import 'package:flutter/material.dart';

/// 语义化颜色令牌（超出 [ColorScheme] 的应用专属语义色）。
///
/// 作为 [ThemeExtension] 注入 [ThemeData.extensions]，随亮暗/变体变化。
/// 取值：`Theme.of(context).extension<AppColors>()!` 或便捷扩展 `context.appColors`。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.danger,
    required this.onDanger,
    required this.info,
    required this.ratingStar,
    required this.playAction,
    required this.onPlayAction,
    required this.progressTrack,
    required this.progressActive,
    required this.scrim,
    required this.scrimStrong,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.badge4k,
    required this.badgeHdr,
    required this.badgeDolbyVision,
    required this.badgeAtmos,
    required this.badgeForeground,
  });

  /// 成功 / 已播放 / 完成
  final Color success;
  final Color onSuccess;

  /// 警告（部分受限、转码降级等）
  final Color warning;
  final Color onWarning;

  /// 危险 / 错误 / 删除
  final Color danger;
  final Color onDanger;

  /// 提示（中性信息）
  final Color info;

  /// 评分星标金
  final Color ratingStar;

  /// 海报播放按钮强调色（影院绿）
  final Color playAction;
  final Color onPlayAction;

  /// 进度条底槽 / 已观看进度
  final Color progressTrack;
  final Color progressActive;

  /// 遮罩（海报悬停、Sheet 背景）
  final Color scrim;
  final Color scrimStrong;

  /// 骨架屏底色与高光（自制 shimmer）
  final Color skeletonBase;
  final Color skeletonHighlight;

  /// 媒体规格徽章规范色（对齐主流播放器约定）
  final Color badge4k;
  final Color badgeHdr;
  final Color badgeDolbyVision;
  final Color badgeAtmos;
  final Color badgeForeground;

  /// 亮色主题语义色。
  factory AppColors.light(ColorScheme cs) {
    return AppColors(
      success: const Color(0xFF2E7D32),
      onSuccess: Colors.white,
      warning: const Color(0xFFF9A825),
      onWarning: const Color(0xFF1A1A1A),
      danger: const Color(0xFFC62828),
      onDanger: Colors.white,
      info: const Color(0xFF1565C0),
      ratingStar: const Color(0xFFF5B100),
      playAction: const Color(0xFF2E9E4F),
      onPlayAction: Colors.white,
      progressTrack: cs.surfaceContainerHighest,
      progressActive: const Color(0xFF2E9E4F),
      scrim: Colors.black.withValues(alpha: 0.40),
      scrimStrong: Colors.black.withValues(alpha: 0.66),
      skeletonBase: cs.surfaceContainerHighest,
      skeletonHighlight: cs.surfaceContainerLow,
      badge4k: const Color(0xFF1E88E5),
      badgeHdr: const Color(0xFFF5B100),
      badgeDolbyVision: const Color(0xFF5C4A78),
      badgeAtmos: const Color(0xFFB8860B),
      badgeForeground: Colors.white,
    );
  }

  /// 暗色主题语义色。
  factory AppColors.dark(ColorScheme cs) {
    return AppColors(
      success: const Color(0xFF66BB6A),
      onSuccess: const Color(0xFF0A1F0C),
      warning: const Color(0xFFFFCA28),
      onWarning: const Color(0xFF1A1400),
      danger: const Color(0xFFEF5350),
      onDanger: const Color(0xFF2A0A0A),
      info: const Color(0xFF64B5F6),
      ratingStar: const Color(0xFFFFC107),
      playAction: const Color(0xFF43A047),
      onPlayAction: Colors.white,
      progressTrack: Colors.white.withValues(alpha: 0.20),
      progressActive: const Color(0xFF4CAF50),
      scrim: Colors.black.withValues(alpha: 0.48),
      scrimStrong: Colors.black.withValues(alpha: 0.72),
      skeletonBase: cs.surfaceContainerHigh,
      skeletonHighlight: cs.surfaceContainerHighest,
      badge4k: const Color(0xFF42A5F5),
      badgeHdr: const Color(0xFFFFCA28),
      badgeDolbyVision: const Color(0xFF7A6A94),
      badgeAtmos: const Color(0xFFFFD54F),
      badgeForeground: Colors.white,
    );
  }

  @override
  AppColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? danger,
    Color? onDanger,
    Color? info,
    Color? ratingStar,
    Color? playAction,
    Color? onPlayAction,
    Color? progressTrack,
    Color? progressActive,
    Color? scrim,
    Color? scrimStrong,
    Color? skeletonBase,
    Color? skeletonHighlight,
    Color? badge4k,
    Color? badgeHdr,
    Color? badgeDolbyVision,
    Color? badgeAtmos,
    Color? badgeForeground,
  }) {
    return AppColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      info: info ?? this.info,
      ratingStar: ratingStar ?? this.ratingStar,
      playAction: playAction ?? this.playAction,
      onPlayAction: onPlayAction ?? this.onPlayAction,
      progressTrack: progressTrack ?? this.progressTrack,
      progressActive: progressActive ?? this.progressActive,
      scrim: scrim ?? this.scrim,
      scrimStrong: scrimStrong ?? this.scrimStrong,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
      badge4k: badge4k ?? this.badge4k,
      badgeHdr: badgeHdr ?? this.badgeHdr,
      badgeDolbyVision: badgeDolbyVision ?? this.badgeDolbyVision,
      badgeAtmos: badgeAtmos ?? this.badgeAtmos,
      badgeForeground: badgeForeground ?? this.badgeForeground,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      info: Color.lerp(info, other.info, t)!,
      ratingStar: Color.lerp(ratingStar, other.ratingStar, t)!,
      playAction: Color.lerp(playAction, other.playAction, t)!,
      onPlayAction: Color.lerp(onPlayAction, other.onPlayAction, t)!,
      progressTrack: Color.lerp(progressTrack, other.progressTrack, t)!,
      progressActive: Color.lerp(progressActive, other.progressActive, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      scrimStrong: Color.lerp(scrimStrong, other.scrimStrong, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight: Color.lerp(skeletonHighlight, other.skeletonHighlight, t)!,
      badge4k: Color.lerp(badge4k, other.badge4k, t)!,
      badgeHdr: Color.lerp(badgeHdr, other.badgeHdr, t)!,
      badgeDolbyVision: Color.lerp(badgeDolbyVision, other.badgeDolbyVision, t)!,
      badgeAtmos: Color.lerp(badgeAtmos, other.badgeAtmos, t)!,
      badgeForeground: Color.lerp(badgeForeground, other.badgeForeground, t)!,
    );
  }
}

/// 播放器调色板的字面量默认值（单一事实来源）。
///
/// 既供 [PlayerColors.cinema] 使用，也供需要 `const` 上下文的播放器控件
/// （如大量 `const TextStyle`）直接引用，避免双份硬编码。
abstract final class PlayerPaletteDefaults {
  static const Color foreground = Color(0xFFE8E8E8);
  static const Color foregroundDim = Color(0x99E8E8E8);
  static const Color foregroundFaint = Color(0x61E8E8E8);
  static const Color accent = Color(0xFFFFD54F);
  static const Color panel = Color(0xE6121212);
  static const Color panelRaised = Color(0xFF212121);
  static const Color popupBackground = Color(0xF0212121);
  static const Color hudBorder = Color(0x18FFFFFF);
  static const Color trackInactive = Color(0x33FFFFFF);
  static const Color trackBuffer = Color(0x55FFFFFF);
}

/// 播放器影院级调色板。
///
/// 默认深色影院基调（不随浅色主题变白），但仍作为 [ThemeExtension] 注入，
/// 便于将来按主题变体微调或做"纯黑/护眼"播放主题。
@immutable
class PlayerColors extends ThemeExtension<PlayerColors> {
  const PlayerColors({
    required this.foreground,
    required this.foregroundDim,
    required this.foregroundFaint,
    required this.accent,
    required this.panel,
    required this.panelRaised,
    required this.hudBackground,
    required this.hudBorder,
    required this.scrim,
    required this.controlScrim,
    required this.progressTrack,
    required this.progressBuffer,
    required this.progressActive,
  });

  final Color foreground;
  final Color foregroundDim;
  final Color foregroundFaint;
  final Color accent;
  final Color panel;
  final Color panelRaised;
  final Color hudBackground;
  final Color hudBorder;
  final Color scrim;
  final Color controlScrim;
  final Color progressTrack;
  final Color progressBuffer;
  final Color progressActive;

  /// 默认影院深色调色板（沿用历史硬编码值，集中收口）。
  factory PlayerColors.cinema(ColorScheme cs) {
    final semantic = AppColors.dark(cs);
    return PlayerColors(
      foreground: PlayerPaletteDefaults.foreground,
      foregroundDim: PlayerPaletteDefaults.foregroundDim,
      foregroundFaint: PlayerPaletteDefaults.foregroundFaint,
      accent: PlayerPaletteDefaults.accent,
      panel: PlayerPaletteDefaults.panel,
      panelRaised: PlayerPaletteDefaults.panelRaised,
      hudBackground: PlayerPaletteDefaults.panel,
      hudBorder: PlayerPaletteDefaults.hudBorder,
      scrim: Colors.black.withValues(alpha: 0.55),
      controlScrim: Colors.black.withValues(alpha: 0.40),
      progressTrack: PlayerPaletteDefaults.trackInactive,
      progressBuffer: PlayerPaletteDefaults.trackBuffer,
      progressActive: semantic.playAction,
    );
  }

  @override
  PlayerColors copyWith({
    Color? foreground,
    Color? foregroundDim,
    Color? foregroundFaint,
    Color? accent,
    Color? panel,
    Color? panelRaised,
    Color? hudBackground,
    Color? hudBorder,
    Color? scrim,
    Color? controlScrim,
    Color? progressTrack,
    Color? progressBuffer,
    Color? progressActive,
  }) {
    return PlayerColors(
      foreground: foreground ?? this.foreground,
      foregroundDim: foregroundDim ?? this.foregroundDim,
      foregroundFaint: foregroundFaint ?? this.foregroundFaint,
      accent: accent ?? this.accent,
      panel: panel ?? this.panel,
      panelRaised: panelRaised ?? this.panelRaised,
      hudBackground: hudBackground ?? this.hudBackground,
      hudBorder: hudBorder ?? this.hudBorder,
      scrim: scrim ?? this.scrim,
      controlScrim: controlScrim ?? this.controlScrim,
      progressTrack: progressTrack ?? this.progressTrack,
      progressBuffer: progressBuffer ?? this.progressBuffer,
      progressActive: progressActive ?? this.progressActive,
    );
  }

  @override
  PlayerColors lerp(ThemeExtension<PlayerColors>? other, double t) {
    if (other is! PlayerColors) return this;
    return PlayerColors(
      foreground: Color.lerp(foreground, other.foreground, t)!,
      foregroundDim: Color.lerp(foregroundDim, other.foregroundDim, t)!,
      foregroundFaint: Color.lerp(foregroundFaint, other.foregroundFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelRaised: Color.lerp(panelRaised, other.panelRaised, t)!,
      hudBackground: Color.lerp(hudBackground, other.hudBackground, t)!,
      hudBorder: Color.lerp(hudBorder, other.hudBorder, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      controlScrim: Color.lerp(controlScrim, other.controlScrim, t)!,
      progressTrack: Color.lerp(progressTrack, other.progressTrack, t)!,
      progressBuffer: Color.lerp(progressBuffer, other.progressBuffer, t)!,
      progressActive: Color.lerp(progressActive, other.progressActive, t)!,
    );
  }
}

/// 便捷取值扩展。
extension AppColorsX on BuildContext {
  /// 语义色令牌。
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ??
      AppColors.dark(Theme.of(this).colorScheme);

  /// 播放器调色板。
  PlayerColors get playerColors =>
      Theme.of(this).extension<PlayerColors>() ??
      PlayerColors.cinema(Theme.of(this).colorScheme);
}
