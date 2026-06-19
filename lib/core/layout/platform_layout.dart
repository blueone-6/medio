import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';

// ---------------------------------------------------------------------------
// 平台 / 设备 / 断点 / 输入模态框架
// ---------------------------------------------------------------------------

/// True when running on Android — use for mobile-only UI branches.
/// Desktop (Windows/Linux/macOS) and web always return false.
///
/// 注意：该值对 Android TV 也为 true。需要区分手机/平板/TV 时请改用
/// [deviceTypeOf]。保留此 getter 以兼容存量调用点。
bool get isAndroidMobileUi =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// 是否桌面原生平台（Windows / macOS / Linux）。
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

const kMobileHorizontalPadding = 16.0;
const kDesktopHorizontalPadding = 24.0;

/// TV overscan 安全区（10ft UI）。
const kTvSafeArea = 48.0;

/// Android TV 运行标记。
///
/// 纯 Dart 无法可靠探测 TV；真正的 leanback 特征探测由 F-U9 在原生侧
/// （`MainActivity` 通过 MethodChannel）调用 [setAndroidTvDetected] 写入。
/// 在此之前默认为 false，三端框架其余部分已就绪。
bool _androidTvDetected = false;

/// 由原生侧（F-U9）回写 TV 探测结果。
void setAndroidTvDetected(bool value) {
  _androidTvDetected = value;
}

/// 当前是否运行在 Android TV 上。
bool get isAndroidTv => isAndroidMobileUi && _androidTvDetected;

/// Material 3 窗口尺寸类（按宽度）。
enum WindowSizeClass {
  /// < 600dp（手机竖屏）
  compact,

  /// 600–839dp（手机横屏 / 小平板）
  medium,

  /// 840–1199dp（平板横屏 / 小桌面窗口）
  expanded,

  /// >= 1200dp（桌面 / 大屏）
  large,
}

/// 设备形态。
enum DeviceType { phone, tablet, desktop, tv }

/// 主输入模态。
enum InputModality {
  /// 触屏（手势）
  touch,

  /// 指针（鼠标 + 键盘）
  pointer,

  /// 方向键 / 遥控器（D-Pad）
  dpad,
}

/// 由宽度判定窗口尺寸类。
WindowSizeClass windowSizeClassForWidth(double width) {
  if (width < 600) return WindowSizeClass.compact;
  if (width < 840) return WindowSizeClass.medium;
  if (width < 1200) return WindowSizeClass.expanded;
  return WindowSizeClass.large;
}

/// 当前窗口尺寸类。
WindowSizeClass windowSizeClassOf(BuildContext context) =>
    windowSizeClassForWidth(MediaQuery.sizeOf(context).width);

/// 当前设备形态。
///
/// 规则：TV 优先；其次桌面平台；Android 则按尺寸类区分手机/平板。
DeviceType deviceTypeOf(BuildContext context) {
  if (isAndroidTv) return DeviceType.tv;
  if (isDesktopPlatform || kIsWeb) return DeviceType.desktop;
  // Android：用最短边区分手机 / 平板（>= 600dp 视为平板）。
  final shortest = MediaQuery.sizeOf(context).shortestSide;
  return shortest >= 600 ? DeviceType.tablet : DeviceType.phone;
}

/// 当前主输入模态。
InputModality inputModalityOf(BuildContext context) {
  switch (deviceTypeOf(context)) {
    case DeviceType.tv:
      return InputModality.dpad;
    case DeviceType.desktop:
      return InputModality.pointer;
    case DeviceType.phone:
    case DeviceType.tablet:
      return InputModality.touch;
  }
}

/// 水平安全边距（按设备形态）。
double horizontalPaddingOf(BuildContext context) {
  switch (deviceTypeOf(context)) {
    case DeviceType.tv:
      return kTvSafeArea;
    case DeviceType.desktop:
    case DeviceType.tablet:
      return kDesktopHorizontalPadding;
    case DeviceType.phone:
      return kMobileHorizontalPadding;
  }
}

/// 海报网格最小列宽（按设备形态，TV/桌面更大以适配远距离观看与指针）。
double posterMinTileWidthOf(BuildContext context) {
  switch (deviceTypeOf(context)) {
    case DeviceType.tv:
      return 160;
    case DeviceType.desktop:
      return 132;
    case DeviceType.tablet:
      return 120;
    case DeviceType.phone:
      return 104;
  }
}

extension PlatformLayoutX on BuildContext {
  DeviceType get deviceType => deviceTypeOf(this);
  WindowSizeClass get windowSizeClass => windowSizeClassOf(this);
  InputModality get inputModality => inputModalityOf(this);
  bool get isTvUi => deviceTypeOf(this) == DeviceType.tv;
  bool get isPhoneUi => deviceTypeOf(this) == DeviceType.phone;
  bool get isTabletUi => deviceTypeOf(this) == DeviceType.tablet;
  bool get isDesktopUi => deviceTypeOf(this) == DeviceType.desktop;
}
