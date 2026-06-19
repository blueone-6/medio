/// 统一高度（elevation）标尺，对齐 Material 3 tonal elevation 档位。
/// 与亮暗主题无关，故为常量类。
abstract final class AppElevation {
  /// 平铺，无投影（默认表面）
  static const double level0 = 0;

  /// 轻微抬升（AppBar 滚动后、卡片悬停）
  static const double level1 = 1;

  /// 卡片选中 / chip 抬升
  static const double level2 = 3;

  /// 浮层 / 菜单
  static const double level3 = 6;

  /// 对话框 / BottomSheet
  static const double level4 = 8;

  /// FAB 按下 / 最高浮层
  static const double level5 = 12;
}
