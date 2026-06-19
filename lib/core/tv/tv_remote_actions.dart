import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 遥控器 / D-Pad 媒体键意图。方向键交给 Flutter 默认的
/// [DirectionalFocusIntent] 焦点遍历；此处只补媒体专用键。
class TvBackIntent extends Intent {
  const TvBackIntent();
}

class TvPlayPauseIntent extends Intent {
  const TvPlayPauseIntent();
}

class TvFastForwardIntent extends Intent {
  const TvFastForwardIntent();
}

class TvRewindIntent extends Intent {
  const TvRewindIntent();
}

/// OK / Select keys on Android TV remotes.
abstract final class TvRemoteSelectKeys {
  static bool isSelect(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButton1 ||
      key == LogicalKeyboardKey.gameButtonA ||
      key == LogicalKeyboardKey.space;
}

/// 方向键集合，供 [TvKeyboardHandler] 长按重复滚动使用。
abstract final class TvRemoteArrowKeys {
  static bool isArrow(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight;
}

/// TV 遥控键到意图的标准映射，供 [Shortcuts] 使用。
///
/// 注意：方向键（上下左右）与 OK（select/enter）由 Flutter 焦点系统默认处理，
/// 因此 TV 上只需保证可聚焦控件（已由 [TvFocusRing] 等提供）。
const Map<ShortcutActivator, Intent> tvRemoteShortcuts = {
  SingleActivator(LogicalKeyboardKey.goBack): TvBackIntent(),
  SingleActivator(LogicalKeyboardKey.escape): TvBackIntent(),
  SingleActivator(LogicalKeyboardKey.mediaPlayPause): TvPlayPauseIntent(),
  SingleActivator(LogicalKeyboardKey.mediaPlay): TvPlayPauseIntent(),
  SingleActivator(LogicalKeyboardKey.mediaPause): TvPlayPauseIntent(),
  SingleActivator(LogicalKeyboardKey.mediaFastForward): TvFastForwardIntent(),
  SingleActivator(LogicalKeyboardKey.mediaRewind): TvRewindIntent(),
};

/// 便捷包裹：为子树注册遥控媒体键意图与处理回调。
class TvRemoteActions extends StatelessWidget {
  const TvRemoteActions({
    super.key,
    required this.child,
    this.onBack,
    this.onPlayPause,
    this.onFastForward,
    this.onRewind,
  });

  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onPlayPause;
  final VoidCallback? onFastForward;
  final VoidCallback? onRewind;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: tvRemoteShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          TvBackIntent: CallbackAction<TvBackIntent>(
            onInvoke: (_) {
              onBack?.call();
              return null;
            },
          ),
          TvPlayPauseIntent: CallbackAction<TvPlayPauseIntent>(
            onInvoke: (_) {
              onPlayPause?.call();
              return null;
            },
          ),
          TvFastForwardIntent: CallbackAction<TvFastForwardIntent>(
            onInvoke: (_) {
              onFastForward?.call();
              return null;
            },
          ),
          TvRewindIntent: CallbackAction<TvRewindIntent>(
            onInvoke: (_) {
              onRewind?.call();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
