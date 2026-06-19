import 'package:media_kit/media_kit.dart';

import '../core/logging/app_log.dart';
import '../core/player/player_subtitle_visibility.dart';
import '../core/player/subtitle_switch_queue.dart';

/// Owns a long-lived [Player] for the app (single active playback).
class PlayerService {
  Player? _player;

  Player get player => _player ??= _createPlayer();

  Player _createPlayer() {
    // libass:true — PGSSUB must be composited by libmpv into the video texture (media-kit #1371).
    // Text tracks override with sub-ass=no + sub-visibility=no to avoid duplicate Flutter overlay.
    const libass = true;
    AppLog.instance.i('PlayerService', 'creating Player libass=$libass');
    final player = Player(
      configuration: const PlayerConfiguration(libass: libass),
    );
    AppLog.instance.i(
      'SubtitleDiag',
      'Player created hash=${identityHashCode(player)} libass=$libass',
    );
    return player;
  }

  /// New playback session: drop cached mpv/VideoController state (hwdec, sid, etc.).
  void disposePlayer() {
    final player = _player;
    if (player != null) {
      SubtitleSwitchQueue.reset();
      resetPlayerSubtitleConfigureCache(player);
      player.dispose();
      _player = null;
    }
  }

  /// Release [player] only if it is still the active app player.
  ///
  /// Episode switches use route replacement, so the old page may dispose after
  /// the new page has already created a fresh player. In that case the old page
  /// must not tear down the new playback session.
  void disposePlayerIfCurrent(Player player) {
    if (!identical(_player, player)) return;
    disposePlayer();
  }

  void dispose() => disposePlayer();
}
