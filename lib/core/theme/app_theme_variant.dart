import 'package:flutter/material.dart';

/// 应用支持的主题配色方案（仅 accent，背景见 [AppNeutralScheme]）。
enum AppThemeVariant {
  /// 跟随系统
  system('跟随系统', null),

  indigo('靛蓝', Color(0xFF3F51B5)),
  /// Teal
  teal('青绿', Color(0xFF009688)),
  /// Rose
  rose('玫红', Color(0xFFE91E63)),
  /// Amber — StreamLux cinematic gold（默认配色）
  amber('琥珀', Color(0xFFFFB800)),
  /// Purple
  purple('紫罗兰', Color(0xFF7C4DFF)),
  /// Cyan
  cyan('青空', Color(0xFF00BCD4)),
  /// Lime
  lime('新绿', Color(0xFF8BC34A)),
  /// Deep Orange
  deepOrange('暖橙', Color(0xFFFF5722)),

  /// 低饱和强调色
  pureDark('纯黑', null);

  const AppThemeVariant(this.label, this.seedColor);

  final String label;
  /// 设置页浅色预览色块（深色强调色见 [AppAccentPalette]）。
  final Color? seedColor;
}

/// 主题亮度模式。
enum AppThemeBrightness {
  system('跟随系统'),
  light('浅色'),
  dark('深色');

  const AppThemeBrightness(this.label);
  final String label;
}
