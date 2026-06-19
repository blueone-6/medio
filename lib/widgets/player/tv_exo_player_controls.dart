import 'package:flutter/material.dart';

import '../../core/player/tv_exo/tv_exo_player.dart';
import '../tv/tv_focus_ring.dart';
import '../../core/theme/app_colors.dart' show PlayerPaletteDefaults;
import '../../core/theme/app_radius.dart';

/// Compact TV playback bar for ExoPlayer (D-Pad friendly).
class TvExoPlayerControls extends StatelessWidget {
  const TvExoPlayerControls({
    super.key,
    required this.state,
    required this.onPlayPause,
    required this.onSeek,
    this.onUserInteraction,
    this.showEpisodeControls = false,
    this.hasPreviousEpisode = false,
    this.hasNextEpisode = false,
    this.onPreviousEpisode,
    this.onNextEpisode,
    this.onToggleEpisodeList,
    this.episodeListOpen = false,
  });

  final TvExoPlayerState state;
  final VoidCallback onPlayPause;
  final void Function(Duration position) onSeek;
  final VoidCallback? onUserInteraction;
  final bool showEpisodeControls;
  final bool hasPreviousEpisode;
  final bool hasNextEpisode;
  final VoidCallback? onPreviousEpisode;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onToggleEpisodeList;
  final bool episodeListOpen;

  static const _foreground = Color(0xFFE8E8E8);

  String _format(Duration d) {
    final total = d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final durMs = state.duration.inMilliseconds;
    final posMs = state.position.inMilliseconds;
    final fraction = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: PlayerPaletteDefaults.accent,
                inactiveTrackColor: const Color(0x44FFFFFF),
                thumbColor: PlayerPaletteDefaults.accent,
              ),
              child: Slider(
                value: fraction,
                onChanged: durMs > 0
                    ? (v) {
                        onUserInteraction?.call();
                        onSeek(Duration(milliseconds: (v * durMs).round()));
                      }
                    : null,
              ),
            ),
            Row(
              children: [
                Text(
                  _format(state.position),
                  style: const TextStyle(color: _foreground, fontSize: 13),
                ),
                const Text(' / ', style: TextStyle(color: Color(0x88E8E8E8))),
                Text(
                  _format(state.duration),
                  style: const TextStyle(color: Color(0xAAE8E8E8), fontSize: 13),
                ),
                const Spacer(),
                if (showEpisodeControls) ...[
                  _btn(
                    icon: Icons.skip_previous_rounded,
                    onPressed: hasPreviousEpisode ? onPreviousEpisode : null,
                  ),
                  const SizedBox(width: 4),
                ],
                _btn(
                  icon: state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onPressed: onPlayPause,
                  filled: true,
                  autofocus: true,
                ),
                if (showEpisodeControls) ...[
                  const SizedBox(width: 4),
                  _btn(
                    icon: Icons.skip_next_rounded,
                    onPressed: hasNextEpisode ? onNextEpisode : null,
                  ),
                  const SizedBox(width: 8),
                  _btn(
                    icon: episodeListOpen
                        ? Icons.close_rounded
                        : Icons.playlist_play_rounded,
                    onPressed: onToggleEpisodeList,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn({
    required IconData icon,
    VoidCallback? onPressed,
    bool filled = false,
    bool autofocus = false,
  }) {
    final child = Icon(icon, color: filled ? Colors.black : _foreground, size: 22);
    final size = filled ? 44.0 : 40.0;
    final material = Material(
      color: filled ? PlayerPaletteDefaults.accent : const Color(0x33FFFFFF),
      borderRadius: AppRadius.smR,
      child: InkWell(
        borderRadius: AppRadius.smR,
        onTap: onPressed == null
            ? null
            : () {
                onUserInteraction?.call();
                onPressed();
              },
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    );
    if (onPressed == null) return material;
    return TvFocusRing(
      autofocus: autofocus,
      onActivate: () {
        onUserInteraction?.call();
        onPressed();
      },
      child: material,
    );
  }
}
