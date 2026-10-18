import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/player/exo/exo_track_selection.dart';
import '../../core/player/exo/video_fit_mode.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../models/emby/emby_subtitle_option.dart';
import 'player_menu_sheet.dart';

/// Bottom playback bar for the ExoPlayer phone screen.
///
/// Visual language mirrors [PlayerControls]' compact/landscape rows, but the
/// engine surface is the ExoPlayer bridge (tracks, volume, speed, subtitle
/// targets) instead of media_kit.
class ExoPlayerControls extends StatefulWidget {
  const ExoPlayerControls({
    super.key,
    required this.state,
    required this.onPlayPause,
    required this.onSeekTo,
    required this.onVolumeChanged,
    required this.muted,
    required this.embySubtitles,
    required this.nativeTextTracks,
    required this.audioTracks,
    this.unsupportedAudioTracks = const [],
    required this.currentSubtitle,
    required this.onSubtitlePicked,
    required this.currentAudio,
    required this.onAudioPicked,
    required this.speed,
    required this.onRatePicked,
    required this.videoFitMode,
    required this.onVideoFitModePicked,
    required this.readSubtitleOffsetMs,
    required this.onAdjustSubtitleDelay,
    required this.onResetSubtitleDelay,
    this.gestureSeekPreviewSeconds,
    this.isFullScreen = false,
    this.onToggleFullScreen,
    this.showEpisodeControls = false,
    this.hasPreviousEpisode = false,
    this.hasNextEpisode = false,
    this.onPreviousEpisode,
    this.onNextEpisode,
    this.episodeListOpen = false,
    this.onToggleEpisodeList,
    this.onUserInteraction,
  });

  /// Playback snapshot consumed by the bar.
  final ExoPlayerControlsStateSnapshot state;
  final VoidCallback onPlayPause;
  final Future<void> Function(Duration target) onSeekTo;

  /// Volume target on the 0–100 scale.
  final ValueChanged<double> onVolumeChanged;
  final bool muted;

  final List<EmbySubtitleOption> embySubtitles;
  final List<ExoPlayerTrack> nativeTextTracks;
  final List<ExoPlayerTrack> audioTracks;

  /// Audio tracks the container has but this device cannot decode (e.g. EAC3
  /// without a Dolby decoder). Shown as an explanation instead of an empty list.
  final List<ExoPlayerTrack> unsupportedAudioTracks;

  final ExoSubtitleTarget? currentSubtitle;
  final ValueChanged<ExoSubtitleTarget> onSubtitlePicked;
  final ExoPlayerTrack? currentAudio;
  final ValueChanged<ExoPlayerTrack?> onAudioPicked;

  final double speed;
  final ValueChanged<double> onRatePicked;

  /// Video scaling mode (适应 / 裁剪铺满 / 填满宽度 / 填满高度 / 拉伸填满).
  final VideoFitMode videoFitMode;
  final ValueChanged<VideoFitMode> onVideoFitModePicked;

  /// Live subtitle offset in ms. A plain value would go stale: the chrome
  /// auto-hides after 4 s and disposes this widget while the picker sheet stays
  /// open, so the sheet must read the current offset through this getter.
  final ValueGetter<int> readSubtitleOffsetMs;
  final void Function(int deltaMs) onAdjustSubtitleDelay;
  final VoidCallback onResetSubtitleDelay;

  final ValueListenable<int>? gestureSeekPreviewSeconds;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;
  final bool showEpisodeControls;
  final bool hasPreviousEpisode;
  final bool hasNextEpisode;
  final VoidCallback? onPreviousEpisode;
  final VoidCallback? onNextEpisode;
  final bool episodeListOpen;
  final VoidCallback? onToggleEpisodeList;
  final VoidCallback? onUserInteraction;

  @override
  State<ExoPlayerControls> createState() => _ExoPlayerControlsState();
}

/// Subset of the bridge state the controls render from.
class ExoPlayerControlsStateSnapshot {
  const ExoPlayerControlsStateSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.volume = 100,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final double volume;
}

class _ExoPlayerControlsState extends State<ExoPlayerControls> {
  static const _foreground = Color(0xFFE8E8E8);
  static const _foregroundDim = Color(0xAAE8E8E8);
  static const _hitSize = 44.0;
  static const _iconSize = 24.0;
  static const _btnSpacing = 6.0;
  static const _groupSpacing = 12.0;
  static const _barPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 6);
  static const _playbackRates = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static const _volumeAutoHideDelay = Duration(seconds: 3);

  double? _timelineDragValue;
  double? _timelineHoverFraction;
  bool _volumeSliderVisible = false;
  Timer? _volumeHideTimer;

  @override
  void dispose() {
    _volumeHideTimer?.cancel();
    super.dispose();
  }

  void _notify() => widget.onUserInteraction?.call();

  // ── formatting ──

  static String _fmtHms(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static String _fmtOffset(int ms) {
    final seconds = ms / 1000.0;
    final fixed = seconds.abs().toStringAsFixed(1);
    return seconds == 0 ? '0.0s' : '${seconds > 0 ? '+' : '-'}${fixed}s';
  }

  // ── transport ──

  void _playPause() {
    _notify();
    widget.onPlayPause();
  }

  Future<void> _seekBy(int seconds) async {
    _notify();
    final cur = widget.state.position;
    final dur = widget.state.duration;
    var next = cur + Duration(seconds: seconds);
    if (next < Duration.zero) next = Duration.zero;
    if (dur > Duration.zero && next > dur) next = dur;
    await widget.onSeekTo(next);
  }

  // ── volume ──

  void _showVolumeSlider() {
    _notify();
    setState(() => _volumeSliderVisible = true);
    _volumeHideTimer?.cancel();
    _volumeHideTimer = Timer(_volumeAutoHideDelay, () {
      if (mounted) setState(() => _volumeSliderVisible = false);
    });
  }

  void _changeVolume(double v) {
    _notify();
    _showVolumeSlider();
    widget.onVolumeChanged(v.clamp(0.0, 100.0));
  }

  IconData _volumeIcon(double vol) {
    if (widget.muted || vol <= 0) return Icons.volume_off_rounded;
    if (vol < 33) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  // ── sheets ──

  Future<void> _showPlayerMenuSheet({
    required String title,
    required List<PlayerMenuRow> Function(
      VoidCallback popSheet,
      VoidCallback refresh,
    ) rowsBuilder,
    bool showCount = false,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: const Color(0x66000000),
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        void popSheet() => Navigator.of(dialogContext).pop();
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final rows = rowsBuilder(popSheet, () => setSheetState(() {}));
            final count = showCount
                ? rows.where((r) => r.sectionTitle == null).length
                : null;
            return Center(
              child: PlayerMenuSheet(
                title: title,
                countText: count == null ? null : '$count 条',
                rows: rows,
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  List<PlayerMenuRow> _buildSubtitleRows(
    VoidCallback popSheet,
    VoidCallback refresh,
  ) {
    final current = widget.currentSubtitle;
    // Only streams the app can actually fetch belong here; embedded tracks are
    // listed under 内嵌 from the native track list (`externalSubtitleChoices`
    // explains the fallback when the container exposes no text track).
    final external = externalSubtitleChoices(
      embySubtitles: widget.embySubtitles,
      nativeTextTracks: widget.nativeTextTracks,
    );
    final muxed = widget.nativeTextTracks;

    void select(ExoSubtitleTarget target) {
      popSheet();
      widget.onSubtitlePicked(target);
    }

    // Native-rendered (muxed/bitmap) tracks can only be *delayed* — media3
    // exposes just the currently-active cues, so showing them earlier is not
    // possible. Say so instead of leaving a tap that looks broken.
    final nativeActive = current is ExoSubtitleMuxed;

    void adjust(int deltaMs) {
      widget.onAdjustSubtitleDelay(deltaMs);
      refresh();
    }

    void reset() {
      widget.onResetSubtitleDelay();
      refresh();
    }

    final rows = <PlayerMenuRow>[
      PlayerMenuRow(
        label: '关闭字幕',
        selected: current is ExoSubtitleOff,
        onTap: () => select(const ExoSubtitleOff()),
      ),
      if (muxed.isNotEmpty) PlayerMenuRow(sectionTitle: '内嵌（${muxed.length}）'),
      for (final t in muxed)
        PlayerMenuRow(
          label: t.label,
          value: t.language,
          selected: current is ExoSubtitleMuxed && current.track.id == t.id,
          onTap: () => select(ExoSubtitleMuxed(t)),
        ),
      if (external.isNotEmpty) PlayerMenuRow(sectionTitle: '外挂（${external.length}）'),
      for (final o in external)
        PlayerMenuRow(
          label: o.label,
          value: o.isForced ? '强制' : null,
          selected:
              current is ExoSubtitleExternal && current.option.index == o.index,
          onTap: () => select(ExoSubtitleExternal(o)),
        ),
      PlayerMenuRow(
        sectionTitle: '字幕同步（当前 ${_fmtOffset(widget.readSubtitleOffsetMs())}）',
      ),
      PlayerMenuRow(
        label: '提前 0.5s',
        value: nativeActive ? '位图/内嵌仅支持延后' : null,
        onTap: () => adjust(-500),
      ),
      PlayerMenuRow(
        label: '延后 0.5s',
        onTap: () => adjust(500),
      ),
      PlayerMenuRow(
        label: '重置同步',
        onTap: reset,
      ),
    ];
    return rows;
  }

  Future<void> _showSubtitlePicker() async {
    _notify();
    await _showPlayerMenuSheet(
      title: '字幕',
      showCount: true,
      rowsBuilder: _buildSubtitleRows,
    );
  }

  List<PlayerMenuRow> _buildAudioRows(
    VoidCallback popSheet,
    VoidCallback refresh,
  ) {
    final current = widget.currentAudio;
    if (widget.audioTracks.isEmpty &&
        widget.unsupportedAudioTracks.isNotEmpty) {
      // The container has audio, the device just cannot decode it — say so
      // rather than presenting an empty 音轨 list and silent playback.
      final codec = widget.unsupportedAudioTracks.first.label.toUpperCase();
      return [
        PlayerMenuRow(
          label: '$codec 音轨 · 此设备无法解码',
          value: '无声播放',
          onTap: null,
        ),
      ];
    }
    return [
      for (final t in widget.audioTracks)
        PlayerMenuRow(
          label: t.label,
          value: t.language,
          selected: current?.id == t.id,
          onTap: () {
            popSheet();
            widget.onAudioPicked(t);
          },
        ),
    ];
  }

  Future<void> _showAudioPicker() async {
    _notify();
    await _showPlayerMenuSheet(
      title: '音轨',
      showCount: true,
      rowsBuilder: _buildAudioRows,
    );
  }

  // ── widgets ──

  Widget _spacer(double w) => SizedBox(width: w);

  Widget _playButton() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: context.playerColors.accent,
        borderRadius: AppRadius.smR,
      ),
      child: IconButton(
        style: IconButton.styleFrom(
          iconSize: 24,
          foregroundColor: const Color(0xFF1A1A1A),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        tooltip: widget.state.isPlaying ? '暂停' : '播放',
        icon: Icon(
          widget.state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        ),
        onPressed: _playPause,
      ),
    );
  }

  Widget _compactIconBtn(
    IconData icon,
    String tooltip,
    Color color,
    VoidCallback? onPressed,
  ) {
    return SizedBox(
      width: _hitSize,
      height: _hitSize,
      child: IconButton(
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        tooltip: tooltip,
        icon: Icon(icon, size: _iconSize),
        color: color,
        onPressed: onPressed == null
            ? null
            : () {
                _notify();
                onPressed();
              },
      ),
    );
  }

  IconData get _fitModeIcon => switch (widget.videoFitMode) {
        VideoFitMode.fit => Icons.fit_screen_outlined,
        VideoFitMode.zoom => Icons.aspect_ratio_rounded,
        VideoFitMode.fill => Icons.open_in_full_rounded,
      };

  /// Picture scaling button (landscape only — portrait is always 适应).
  ///
  /// Tap cycles 适应 → 裁剪铺满 → 填满宽度 → 填满高度 → 拉伸填满 → 适应.
  Widget _buildFitModeButton({required bool withLabel}) {
    final tooltip =
        '画面：${widget.videoFitMode.label}（${widget.videoFitMode.description}）';
    final button = _compactIconBtn(
      _fitModeIcon,
      tooltip,
      widget.videoFitMode == VideoFitMode.fit ? _foregroundDim : _foreground,
      () => widget.onVideoFitModePicked(widget.videoFitMode.next),
    );
    if (!withLabel) return button;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      button,
      SizedBox(
        height: _hitSize,
        child: Center(
          child: Text(
            widget.videoFitMode.shortLabel,
            style: TextStyle(
              color: widget.videoFitMode == VideoFitMode.fit
                  ? _foregroundDim
                  : context.playerColors.accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildRateMenu() {
    final accent = context.playerColors.accent;
    return PopupMenuButton<double>(
      tooltip: '倍速',
      color: const Color(0xF21A1A1A),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black54,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onOpened: _notify,
      itemBuilder: (ctx) => [
        for (final r in _playbackRates)
          PopupMenuItem(
            value: r,
            height: 42,
            child: Text(
              r == 1.0 ? '正常' : '${r}x',
              style: TextStyle(
                color: widget.speed == r ? accent : _foreground,
                fontSize: 13,
              ),
            ),
          ),
      ],
      onSelected: (r) {
        _notify();
        widget.onRatePicked(r);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          widget.speed == 1.0 ? '倍速' : '${_trimRate(widget.speed)}x',
          style: const TextStyle(
            color: _foreground,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  static String _trimRate(double r) {
    if (r == r.roundToDouble()) return r.toStringAsFixed(0);
    return r.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }

  Widget _buildVolumePopover() {
    final vol = widget.state.volume;
    return Container(
      width: 260,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xE61A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        children: [
          Icon(
            _volumeIcon(vol),
            color: widget.muted ? context.playerColors.accent : _foreground,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: context.playerColors.accent,
                inactiveTrackColor: const Color(0x44FFFFFF),
                thumbColor: context.playerColors.accent,
              ),
              child: Slider(
                value: vol.clamp(0.0, 100.0),
                onChanged: _changeVolume,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              widget.muted ? '静音' : '${vol.round()}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _foregroundDim,
                fontSize: 11.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final preview = widget.gestureSeekPreviewSeconds;
        Widget timelineBody(int previewSeconds) {
          final pos = widget.state.position;
          final dur = widget.state.duration;
          final durKnown = dur.inMilliseconds > 1000;
          final maxMs = durKnown ? dur.inMilliseconds : 1;
          final progress =
              durKnown ? (pos.inMilliseconds / maxMs).clamp(0.0, 1.0) : 0.0;

          Duration displayPos = pos;
          var displayProgress = progress;
          final dragging = _timelineDragValue != null;
          if (dragging) {
            displayProgress = _timelineDragValue!;
            displayPos = Duration(
              milliseconds:
                  (_timelineDragValue! * maxMs).round().clamp(0, maxMs),
            );
          } else if (previewSeconds != 0 && maxMs > 1) {
            final targetMs =
                (pos.inMilliseconds + previewSeconds * 1000).clamp(0, maxMs);
            displayPos = Duration(milliseconds: targetMs);
            displayProgress = targetMs / maxMs;
          }
          final previewing = dragging || previewSeconds != 0;
          return Row(children: [
            SizedBox(
              width: 72,
              child: Text(
                _fmtHms(displayPos),
                style: TextStyle(
                  color: previewing
                      ? context.playerColors.accent
                      : _foregroundDim,
                  fontSize: 11.5,
                  fontWeight: previewing ? FontWeight.w600 : FontWeight.normal,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (ctx, c) {
                final w = c.maxWidth;
                final hf = _timelineHoverFraction;
                Duration? hoverDur;
                if (hf != null) {
                  hoverDur = Duration(
                      milliseconds: (hf * maxMs).round().clamp(0, maxMs));
                }
                final tipFraction = _timelineDragValue ?? hf;
                Duration? tipDur;
                if (dragging) {
                  tipDur = displayPos;
                } else if (hoverDur != null) {
                  tipDur = hoverDur;
                }
                final displayVal = displayProgress.clamp(0.0, 1.0);
                const tipHalf = 30.0;
                return SizedBox(
                  height: 28,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Center(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: context.playerColors.progressTrack,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: displayVal,
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: context.playerColors.progressActive,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: ((displayVal * w) - 4).clamp(0.0, w - 8),
                        child: IgnorePointer(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: context.playerColors.progressActive,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: context.playerColors.progressActive
                                      .withValues(alpha: 0.45),
                                  blurRadius: 4,
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                      MouseRegion(
                        hitTestBehavior: HitTestBehavior.translucent,
                        onHover: (e) {
                          _notify();
                          setState(() => _timelineHoverFraction =
                              (e.localPosition.dx / w).clamp(0.0, 1.0));
                        },
                        onExit: (_) =>
                            setState(() => _timelineHoverFraction = null),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (_) {
                            _notify();
                            if (_timelineDragValue == null) {
                              setState(() => _timelineDragValue = progress);
                            }
                          },
                          onHorizontalDragUpdate: (d) {
                            _notify();
                            final dx = d.localPosition.dx;
                            setState(() => _timelineDragValue =
                                (dx / w).clamp(0.0, 1.0));
                          },
                          onHorizontalDragEnd: (_) {
                            final v = _timelineDragValue;
                            if (v != null) {
                              setState(() => _timelineDragValue = null);
                              if (maxMs <= 1) return;
                              _notify();
                              unawaited(widget.onSeekTo(
                                Duration(milliseconds: (v * maxMs).round()),
                              ));
                            }
                          },
                          onHorizontalDragCancel: () {
                            if (_timelineDragValue != null) {
                              setState(() => _timelineDragValue = null);
                            }
                          },
                          onTapDown: (d) {
                            _notify();
                            if (maxMs <= 1) return;
                            final x = d.localPosition.dx;
                            unawaited(widget.onSeekTo(
                              Duration(milliseconds:
                                  ((x / w) * maxMs).round().clamp(0, maxMs)),
                            ));
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),
                      if (tipDur != null && tipFraction != null)
                        Positioned(
                          left: (tipFraction * w - tipHalf)
                              .clamp(4.0, w - tipHalf * 2),
                          top: dragging ? -32 : -26,
                          child: IgnorePointer(
                            child: Material(
                              color: const Color(0xE61A1A1A),
                              borderRadius: BorderRadius.circular(6),
                              elevation: 4,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: dragging ? 10 : 8,
                                  vertical: dragging ? 5 : 4,
                                ),
                                child: Text(
                                  dragging
                                      ? '${_fmtHms(tipDur)} / ${_fmtHms(dur)}'
                                      : _fmtHms(tipDur),
                                  style: TextStyle(
                                    color: _foreground,
                                    fontSize: dragging ? 12.5 : 11.5,
                                    fontWeight: dragging
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
            SizedBox(
              width: 72,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _fmtHms(dur),
                  style: const TextStyle(
                    color: _foregroundDim,
                    fontSize: 11.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ]);
        }

        if (preview == null) {
          return timelineBody(0);
        }
        return ValueListenableBuilder<int>(
          valueListenable: preview,
          builder: (context, previewSeconds, _) => timelineBody(previewSeconds),
        );
      },
    );
  }

  Widget _buildTransportGroup({bool includeEpisodeNav = true}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (widget.showEpisodeControls && includeEpisodeNav)
        _compactIconBtn(
          Icons.skip_previous_rounded,
          '上一集',
          widget.hasPreviousEpisode ? _foreground : _foregroundDim,
          widget.hasPreviousEpisode ? widget.onPreviousEpisode : null,
        ),
      _spacer(_btnSpacing),
      _compactIconBtn(
        Icons.replay_10_rounded,
        '后退 10 秒',
        _foreground,
        () => unawaited(_seekBy(-10)),
      ),
      _spacer(_btnSpacing),
      _playButton(),
      _spacer(_btnSpacing),
      _compactIconBtn(
        Icons.forward_10_rounded,
        '前进 10 秒',
        _foreground,
        () => unawaited(_seekBy(10)),
      ),
      _spacer(_btnSpacing),
      if (widget.showEpisodeControls && includeEpisodeNav)
        _compactIconBtn(
          Icons.skip_next_rounded,
          '下一集',
          widget.hasNextEpisode ? _foreground : _foregroundDim,
          widget.hasNextEpisode ? widget.onNextEpisode : null,
        ),
    ]);
  }

  /// Landscape: full 3-column layout like [PlayerControls].
  Widget _buildLandscapeRow() {
    final accent = context.playerColors.accent;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _compactIconBtn(
              _volumeIcon(widget.state.volume),
              '音量',
              _foreground,
              _showVolumeSlider,
            ),
            _spacer(_groupSpacing),
            _buildRateMenu(),
            _spacer(_groupSpacing),
            _buildFitModeButton(withLabel: true),
            _spacer(_groupSpacing),
            _compactIconBtn(
              Icons.closed_caption_rounded,
              '字幕',
              _foreground,
              () => unawaited(_showSubtitlePicker()),
            ),
          ]),
        ),
      ),
      _buildTransportGroup(),
      Expanded(
        child: Align(
          alignment: Alignment.centerRight,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _compactIconBtn(
              Icons.audiotrack_rounded,
              '音轨',
              _foreground,
              () => unawaited(_showAudioPicker()),
            ),
            _spacer(_groupSpacing),
            if (widget.showEpisodeControls &&
                widget.onToggleEpisodeList != null)
              _compactIconBtn(
                widget.episodeListOpen
                    ? Icons.playlist_play_rounded
                    : Icons.playlist_play_outlined,
                '选集',
                widget.episodeListOpen ? accent : _foreground,
                widget.onToggleEpisodeList,
              ),
            if (widget.showEpisodeControls &&
                widget.onToggleEpisodeList != null)
              _spacer(_groupSpacing),
            if (widget.onToggleFullScreen != null)
              _compactIconBtn(
                widget.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                widget.isFullScreen ? '退出全屏' : '全屏',
                _foreground,
                widget.onToggleFullScreen,
              ),
          ]),
        ),
      ),
    ]);
  }

  /// Portrait: 选集 left, centered transport, subtitle/fullscreen right.
  ///
  /// Laid out as a [Row] with equal fixed side widths — a [Stack] of centred
  /// groups let the right-hand icons overlap the transport buttons on a narrow
  /// phone screen (the episode group alone is ~244 dp wide, and portrait is
  /// only ~360 dp). Episode prev/next are omitted here (the 选集 panel and
  /// auto-next cover them); landscape has room for all five.
  Widget _buildPortraitRow() {
    const sideWidth = _hitSize * 2;
    return SizedBox(
      height: _hitSize,
      child: Row(
        children: [
          SizedBox(
            width: sideWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: (widget.showEpisodeControls &&
                      widget.onToggleEpisodeList != null)
                  ? _compactIconBtn(
                      widget.episodeListOpen
                          ? Icons.playlist_play_rounded
                          : Icons.playlist_play_outlined,
                      '选集',
                      widget.episodeListOpen
                          ? context.playerColors.accent
                          : _foreground,
                      widget.onToggleEpisodeList,
                    )
                  : null,
            ),
          ),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _buildTransportGroup(includeEpisodeNav: false),
              ),
            ),
          ),
          SizedBox(
            width: sideWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _compactIconBtn(
                  Icons.closed_caption_rounded,
                  '字幕',
                  _foreground,
                  () => unawaited(_showSubtitlePicker()),
                ),
                if (widget.onToggleFullScreen != null)
                  _compactIconBtn(
                    widget.isFullScreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    widget.isFullScreen ? '退出全屏' : '全屏',
                    _foreground,
                    widget.onToggleFullScreen,
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_volumeSliderVisible)
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.only(left: _barPadding.left - 2),
              child: _buildVolumePopover(),
            ),
          ),
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x00121212),
                Color(0xCC0A0A0A),
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: _barPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTimeline(),
                  const SizedBox(height: 6),
                  if (widget.isFullScreen)
                    _buildLandscapeRow()
                  else
                    _buildPortraitRow(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
