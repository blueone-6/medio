import 'package:flutter/widgets.dart';

/// 统一圆角标尺。与亮暗主题无关，故为常量类。
abstract final class AppRadius {
  /// 4 — 徽章 / 小标签
  static const double xs = 4;

  /// 8 — 输入框 / 小按钮 / chip
  static const double sm = 8;

  /// 12 — 卡片 / 海报 / 默认容器
  static const double md = 12;

  /// 16 — 大卡片 / HUD / BottomSheet 顶角
  static const double lg = 16;

  /// 20 — pill 标签栏
  static const double xl = 20;

  /// 28 — 大型 Sheet / 对话框
  static const double xxl = 28;

  /// 全圆（pill / 圆形）
  static const double pill = 999;

  static const BorderRadius xsR = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smR = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdR = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgR = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlR = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius xxlR = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius pillR = BorderRadius.all(Radius.circular(pill));

  /// BottomSheet 顶部圆角。
  static const BorderRadius sheetTop = BorderRadius.only(
    topLeft: Radius.circular(lg),
    topRight: Radius.circular(lg),
  );
}
