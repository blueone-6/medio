import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/layout/platform_layout.dart';
import '../../core/player/player_audio_track.dart';
import '../../core/logging/app_log.dart';
import '../tv/tv_keyboard_handler.dart';
import '../../core/player/apply_emby_subtitle.dart';
import '../../core/player/player_subtitle_visibility.dart';
import '../../core/player/select_embedded_subtitle.dart';
import '../../core/player/emby_subtitle_match.dart';
import '../../core/player/subtitle_emby_index.dart';
import '../../core/player/subtitle_switch_queue.dart';
import '../../core/player/subtitle_track_kind.dart';
import '../../core/player/player_subtitle_delay.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';

import '../../models/emby/emby_subtitle_option.dart';
import '../../providers/settings_provider.dart';
import '../../services/playback_preferences_service.dart';

/// Bottom playback bar — modern timeline + transport controls.
class PlayerControls extends ConsumerStatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.itemId,
    this.embySubtitles = const [],
    this.onUserInteraction,
    this.onSeek,
    this.volumeShowToken,
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
    this.compact = false,
  });

  final Player player;
  final String itemId;
  final List<EmbySubtitleOption> embySubtitles;
  final VoidCallback? onUserInteraction;
  final VoidCallback? onSeek;
  final ValueNotifier<int>? volumeShowToken;

  /// Non-zero while the user scrubs the video via horizontal gesture preview.
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
  final bool compact;

  @override
  ConsumerState<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends ConsumerState<PlayerControls> {
  double? _timelineHoverFraction;
  double? _timelineDragValue;

  String? _activeEmbySubtitleId;
  String? _pendingEmbySubtitleId;
  bool _autoSubtitleActive = false;
  Map<int, SubtitleTrack>? _embyIndexTracks;
  StreamSubscription<Tracks>? _tracksSub;

  bool _volumeSliderVisible = false;
  Timer? _volumeHideTimer;
  static final Object _volumeTapGroup = Object();
  bool _volumeDragging = false;

  late final Stream<void> _playerStateStream;

  static const _playbackRates = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static const _volumeAutoHideDelay = Duration(seconds: 3);

  Player get _player => widget.player;

  bool get _isDpad => context.inputModality == InputModality.dpad;

  void _notify() => widget.onUserInteraction?.call();

  double get _tvBtnSize => 34;

  Widget _transportBtn({
    required IconData icon,
    required String tooltip,
    Color color = _foreground,
    VoidCallback? onPressed,
    bool filled = false,
    Color? fillColor,
    Color? filledIconColor,
    double iconSize = _iconSize,
    double? size,
  }) {
    if (!_isDpad) {
      if (filled) {
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: fillColor ?? color,
            borderRadius: AppRadius.smR,
          ),
          child: IconButton(
            style: IconButton.styleFrom(
              iconSize: iconSize,
              foregroundColor: filledIconColor ?? const Color(0xFF1A1A1A),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            tooltip: tooltip,
            icon: Icon(icon),
            onPressed: onPressed,
          ),
        );
      }
      return IconButton(
        style: _iconStyle,
        tooltip: tooltip,
        icon: Icon(icon, size: iconSize),
        color: color,
        onPressed: onPressed,
      );
    }

    return TvFocusIconButton(
      icon: icon,
      color: filled ? (filledIconColor ?? const Color(0xFF1A1A1A)) : color,
      size: size ?? _tvBtnSize,
      iconSize: iconSize.clamp(16, 22),
      filled: filled,
      fillColor: fillColor,
      borderRadius: AppRadius.sm,
      enabled: onPressed != null,
      onActivate: onPressed,
      onFocusChange: (focused) {
        if (focused) _notify();
      },
    );
  }

  Widget _transportRateBtn(double rate) {
    if (!_isDpad) {
      return Theme(
        data: _popupTheme(context),
        child: PopupMenuButton<double>(
          tooltip: '倍速',
          color: _popupBg,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black54,
          elevation: 10,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onOpened: _notify,
          itemBuilder: (ctx) => [
            for (final r in _playbackRates)
              PopupMenuItem(
                value: r,
                child: _popupRow(
                  selected: (r - rate).abs() < 0.001,
                  label: _fmtRate(r),
                ),
              ),
          ],
          onSelected: _pickRate,
          child: SizedBox(
            height: _hitSize,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Text(
                  _fmtRate(rate),
                  style: const TextStyle(
                    color: _foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return TvFocusIconButton(
      label: _fmtRate(rate),
      color: _foreground,
      size: _tvBtnSize,
      onActivate: () => _showTvRatePicker(rate),
      onFocusChange: (focused) {
        if (focused) _notify();
      },
    );
  }

  Future<void> _showTvRatePicker(double currentRate) async {
    _notify();
    final picked = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _popupBg,
        title: const Text('倍速', style: TextStyle(color: _foreground)),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in _playbackRates)
                TvFocusListTile(
                  title: _fmtRate(r),
                  trailing: (r - currentRate).abs() < 0.001
                      ? Icon(Icons.check, color: _playerAccent(ctx))
                      : null,
                  onActivate: () => Navigator.pop(ctx, r),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) _pickRate(picked);
  }

  void _deferEpisodeListToggle() {
    final toggle = widget.onToggleEpisodeList;
    if (toggle == null) return;
    _notify();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) toggle();
    });
  }

  PlaybackPreferencesService get _playbackPrefs =>
      ref.read(playbackPreferencesServiceProvider);

  Future<void> _persistSubtitleSelection(String? selection) =>
      _playbackPrefs.setSubtitleSelection(widget.itemId, selection);

  bool _restoredSavedSubtitleId = false;

  // ── Theme-aware colors (pinned to a clean dark player aesthetic) ──

  static const _foreground = PlayerPaletteDefaults.foreground;
  static const _foregroundDim = PlayerPaletteDefaults.foregroundDim;
  static const _amber = PlayerPaletteDefaults.accent;

  Color _playerAccent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Use the current theme's primary with adjusted brightness for dark bg
    return HSLColor.fromColor(scheme.primary)
        .withSaturation(0.7)
        .withLightness(0.65)
        .toColor();
  }

  // ── Lifecycle ──

  @override
  void initState() {
    super.initState();
    _playerStateStream = _createPlayerStateStream(widget.player);
    SubtitleSwitchQueue.busy.addListener(_onSubtitleBusyChanged);
    widget.volumeShowToken?.addListener(_onVolumeShowToken);
    _embyIndexTracks = fallbackEmbyIndexTrackMap(
      widget.player.state.tracks,
      widget.embySubtitles,
    );
    _tracksSub = widget.player.stream.tracks.listen((_) {
      unawaited(_refreshEmbyTrackMap());
    });
    unawaited(_refreshEmbyTrackMap());
  }

  void _onSubtitleBusyChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.embySubtitles, widget.embySubtitles)) {
      _embyIndexTracks = fallbackEmbyIndexTrackMap(
        _player.state.tracks,
        widget.embySubtitles,
      );
      unawaited(_refreshEmbyTrackMap());
    }
  }

  @override
  void dispose() {
    SubtitleSwitchQueue.busy.removeListener(_onSubtitleBusyChanged);
    _tracksSub?.cancel();
    widget.volumeShowToken?.removeListener(_onVolumeShowToken);
    _volumeHideTimer?.cancel();
    super.dispose();
  }

  void _onVolumeShowToken() {
    if (!mounted) return;
    _showVolumeSlider();
  }

  Stream<void> _createPlayerStateStream(Player player) {
    final controller = StreamController<void>.broadcast();
    void emit(_) => controller.add(null);
    final sub = <StreamSubscription>[
      player.stream.position.listen(emit),
      player.stream.duration.listen(emit),
      player.stream.volume.listen(emit),
      player.stream.rate.listen(emit),
      player.stream.tracks.listen(emit),
      player.stream.track.listen(emit),
      player.stream.playing.listen(emit),
    ];
    controller.onCancel = () {
      for (final s in sub) {
        s.cancel();
      }
    };
    return controller.stream;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredSavedSubtitleId) return;
    _restoredSavedSubtitleId = true;
    final saved = ref
        .read(playbackPreferencesServiceProvider)
        .getSubtitleSelection(widget.itemId);
    if (saved == PlaybackPreferencesService.subtitleAuto) {
      _autoSubtitleActive = true;
    } else if (saved != null &&
        saved.startsWith(PlaybackPreferencesService.subtitleEmbyPrefix)) {
      _activeEmbySubtitleId = saved;
    }
  }

  // ── Volume ──

  void _scheduleVolumeHide() {
    _volumeHideTimer?.cancel();
    _volumeHideTimer = Timer(_volumeAutoHideDelay, () {
      if (!mounted) return;
      _hideVolumeSlider();
    });
  }

  void _showVolumeSlider() {
    if (_volumeSliderVisible) {
      _scheduleVolumeHide();
      return;
    }
    setState(() => _volumeSliderVisible = true);
    _scheduleVolumeHide();
  }

  void _hideVolumeSlider() {
    _volumeHideTimer?.cancel();
    _volumeDragging = false;
    if (!mounted || !_volumeSliderVisible) return;
    setState(() => _volumeSliderVisible = false);
  }

  void _toggleVolumeSlider() {
    _notify();
    _volumeSliderVisible ? _hideVolumeSlider() : _showVolumeSlider();
  }

  // ── Layout constants ──

  static const _barPadding = EdgeInsets.fromLTRB(14, 8, 14, 10);
  static const _iconSize = 22.0;
  static const _hitSize = 42.0;
  static const _btnSpacing = 2.0;
  static const _groupSpacing = 6.0;

  // ── Popup menu helpers ──

  static const _popupBg = PlayerPaletteDefaults.popupBackground;
  static const _popupSelect = PlayerPaletteDefaults.foreground;

  Widget _popupRow({
    required bool selected,
    required String label,
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: selected
              ? const Icon(Icons.check, size: 16, color: _popupSelect)
              : null,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? _popupSelect : _foreground,
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  ThemeData _popupTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      highlightColor: Colors.white.withValues(alpha: 0.06),
      splashColor: Colors.white.withValues(alpha: 0.10),
      dividerTheme: const DividerThemeData(
          color: Color(0x33FFFFFF), thickness: 0.5, space: 1),
      popupMenuTheme: const PopupMenuThemeData(
        color: _popupBg,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: _foreground, fontSize: 13.5),
      ),
    );
  }

  // ── Formatting ──

  static String _fmtHms(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static String _fmtRate(double r) {
    String s = r.toStringAsFixed(2);
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return '${s}x';
  }

  static String _fmtOffset(int ms) {
    final abs = ms.abs();
    final sec = (abs / 1000).toStringAsFixed(1);
    return ms >= 0 ? '+$sec s' : '-$sec s';
  }

  // ── Seek / Volume actions ──

  void _seekRelative(int seconds) {
    _notify();
    widget.onSeek?.call();
    final cur = _player.state.position;
    final dur = _player.state.duration;
    var next = cur + Duration(seconds: seconds);
    if (next < Duration.zero) next = Duration.zero;
    if (next > dur) next = dur;
    _player.seek(next);
  }

  Future<void> _setVolume(double v, {bool notifyInteraction = true}) async {
    if (notifyInteraction) _notify();
    if (_volumeSliderVisible) _scheduleVolumeHide();
    await _player.setVolume(v.clamp(0, 100));
  }

  // ── Subtitle helpers ──

  void _logSubtitleTracks(String reason) {
    final cur = _player.state.track.subtitle;
    final tracks = _player.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    AppLog.instance.i(
      'Subtitle',
      '$reason current sid=${cur.id} title=${cur.title} lang=${cur.language} '
          'available=${tracks.map((t) => "sid=${t.id}:${t.title ?? t.language ?? "?"}").join(", ")}',
    );
  }

  String _subtitleMenuLabel(SubtitleTrack t) {
    if (t.id == 'auto') return '自动';
    if (t.id == 'no') return '关闭字幕';
    String base;
    if (t.title != null && t.title!.isNotEmpty) {
      base = t.title!;
    } else if (t.language != null && t.language!.isNotEmpty) {
      base = t.language!;
    } else {
      final id = t.id;
      base = id.length > 32 ? '${id.substring(0, 12)}…' : id;
    }
    if (isPgsMuxedSubtitle(t)) return '$base (PGS)';
    return base;
  }

  Future<void> _reapplySubtitleDelay() async {
    final offsetMs = ref.read(settingsServiceProvider).subtitleOffsetMs;
    await _player.setSubtitleDelay(Duration(milliseconds: offsetMs));
  }

  void _showPgsUnavailableHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'PGS 特效字幕需要完整版 libmpv 支持，请选用 Simplified / 外挂 SRT 文本轨。',
        ),
        duration: Duration(seconds: 6),
      ),
    );
  }

  void _showSubtitleBusyHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('字幕切换中，请稍候…'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  bool get _subtitleSwitching => SubtitleSwitchQueue.busy.value;

  void _onSubtitleMenuSelected(Object? v) {
    if (v == null || _subtitleSwitching) {
      if (_subtitleSwitching) _showSubtitleBusyHint();
      return;
    }
    if (v is EmbySubtitleOption) {
      _pickEmbySubtitle(v);
    } else if (v is SubtitleTrack) {
      _pickSubtitle(v);
    }
  }

  void _pickSubtitle(SubtitleTrack t) {
    if (_subtitleSwitching) {
      _showSubtitleBusyHint();
      return;
    }
    _notify();

    final prevAuto = _autoSubtitleActive;
    final prevEmbyId = _activeEmbySubtitleId;

    unawaited(
      SubtitleSwitchQueue.runSerial((gen) async {
        if (!mounted) return;
        setState(() {
          _pendingEmbySubtitleId = null;
          if (t.id == 'auto') {
            _autoSubtitleActive = true;
            _activeEmbySubtitleId = null;
          } else if (t.id == 'no') {
            _autoSubtitleActive = false;
            _activeEmbySubtitleId = null;
          } else {
            _autoSubtitleActive = false;
            _activeEmbySubtitleId = null;
          }
        });

        var ok = true;
        if (t.id == 'no') {
          await SubtitleSwitchQueue.withMpv(
            () => _player.activateSubtitleTrack(t, reason: 'menu_no'),
          );
        } else if (t.id == 'auto') {
          ok = await selectEmbeddedSubtitle(
            player: _player,
            embyOptions: widget.embySubtitles,
            emby: ref.read(embyServiceProvider),
            generation: gen,
          );
        } else if (!t.uri && !t.data) {
          if (!isPgsMuxedSubtitle(t)) {
            final embyOpt = embyTextOptionForMuxed(t, widget.embySubtitles);
            if (embyOpt != null) {
              final emby = ref.read(embyServiceProvider);
              ok = await applyEmbySubtitle(
                player: _player,
                option: embyOpt,
                emby: emby,
                generation: gen,
              );
              if (!mounted || !SubtitleSwitchQueue.isCurrent(gen)) return;
              if (ok) {
                setState(() {
                  _activeEmbySubtitleId = embyOpt.selectionId;
                  _autoSubtitleActive = false;
                });
                await _persistSubtitleSelection(embyOpt.selectionId);
                if (mounted && SubtitleSwitchQueue.isCurrent(gen)) {
                  await _reapplySubtitleDelay();
                }
                return;
              }
            }
          }
          if (!isPgsMuxedSubtitle(t)) {
            ok = false;
          } else {
            ok = await SubtitleSwitchQueue.withMpv(
              () => _player.activateMuxedSubtitle(
                t,
                reason: 'menu_muxed_${t.id}',
              ),
            );
          }
          if (!mounted || !SubtitleSwitchQueue.isCurrent(gen)) return;
          if (!ok && isPgsMuxedSubtitle(t)) _showPgsUnavailableHint();
        } else {
          await SubtitleSwitchQueue.withMpv(
            () =>
                _player.activateSubtitleTrack(t, reason: 'menu_track_${t.id}'),
          );
        }
        if (!mounted || !SubtitleSwitchQueue.isCurrent(gen)) return;

        if (!ok && t.id != 'no' && t.id != 'auto') {
          if (mounted) {
            setState(() {
              _autoSubtitleActive = prevAuto;
              _activeEmbySubtitleId = prevEmbyId;
            });
          }
          return;
        }

        if (t.id == 'no') {
          await _persistSubtitleSelection(
              PlaybackPreferencesService.subtitleOff);
        } else if (t.id == 'auto') {
          await _persistSubtitleSelection(
              PlaybackPreferencesService.subtitleAuto);
          _logSubtitleTracks('manual-auto');
        } else {
          await _persistSubtitleSelection(
              PlaybackPreferencesService.selectionForTrack(t.id));
        }
        if (mounted && SubtitleSwitchQueue.isCurrent(gen)) {
          await _reapplySubtitleDelay();
        }
      }),
    );
  }

  void _pickEmbySubtitle(EmbySubtitleOption option) {
    if (_subtitleSwitching) {
      _showSubtitleBusyHint();
      return;
    }
    _notify();

    final prevAuto = _autoSubtitleActive;
    final prevEmbyId = _activeEmbySubtitleId;

    setState(() {
      _pendingEmbySubtitleId = option.selectionId;
      _autoSubtitleActive = false;
    });

    unawaited(
      SubtitleSwitchQueue.runSerial((gen) async {
        if (!mounted) return;

        final emby = ref.read(embyServiceProvider);
        final native = _embyIndexTracks?[option.index] ??
            fallbackEmbyIndexTrackMap(
              _player.state.tracks,
              widget.embySubtitles,
            )[option.index];
        final ok = await applyEmbySubtitle(
          player: _player,
          option: option,
          emby: emby,
          generation: gen,
          resolvedMuxed: native,
        );
        if (!mounted || !SubtitleSwitchQueue.isCurrent(gen)) return;

        setState(() {
          _pendingEmbySubtitleId = null;
          if (ok) {
            _activeEmbySubtitleId = option.selectionId;
            _autoSubtitleActive = false;
          } else {
            _activeEmbySubtitleId = prevEmbyId;
            _autoSubtitleActive = prevAuto;
            if (option.isBitmapSubtitle) _showPgsUnavailableHint();
          }
        });

        if (!ok) return;
        await _persistSubtitleSelection(option.selectionId);
        if (mounted && SubtitleSwitchQueue.isCurrent(gen)) {
          await _reapplySubtitleDelay();
        }
      }),
    );
  }

  Future<void> _refreshEmbyTrackMap() async {
    final ffIndexMap =
        await buildEmbyIndexTrackMap(_player, widget.embySubtitles);
    if (!mounted) return;
    final fallback = fallbackEmbyIndexTrackMap(
      _player.state.tracks,
      widget.embySubtitles,
    );
    final merged = Map<int, SubtitleTrack>.from(fallback)..addAll(ffIndexMap);
    if (merged.isEmpty) return;

    final prev = _embyIndexTracks;
    if (prev != null &&
        prev.length == merged.length &&
        merged.entries.every((e) => prev[e.key]?.id == e.value.id)) {
      _embyIndexTracks = merged;
      return;
    }
    setState(() => _embyIndexTracks = merged);
  }

  bool _subtitleTrackMatchesEmbyOption(SubtitleTrack t, EmbySubtitleOption o) {
    if (t.id == o.streamUrl) return true;
    if (t.id == o.selectionId) return true;
    if (t.title != null && t.title!.isNotEmpty && t.title == o.label) {
      return true;
    }
    return false;
  }

  bool _isEmbyManagedSubtitleTrack(
      SubtitleTrack t, List<EmbySubtitleOption> emby) {
    for (final o in emby) {
      if (!o.isExternal) continue;
      if (_subtitleTrackMatchesEmbyOption(t, o)) return true;
    }
    return false;
  }

  /// Raw mpv muxed list — only when Emby did not return subtitle metadata.
  List<SubtitleTrack> _nativeMuxedTracks(
      Tracks tracks, List<EmbySubtitleOption> emby) {
    final hasEmbyEmbedded = emby.any((o) => !o.isExternal);
    if (hasEmbyEmbedded) return const [];
    return tracks.subtitle
        .where((t) =>
            t.id != 'auto' &&
            t.id != 'no' &&
            !_isEmbyManagedSubtitleTrack(t, emby))
        .toList();
  }

  bool _showAutoEmbedded(
      List<EmbySubtitleOption> emby, List<SubtitleTrack> nativeMuxed) {
    return emby.any((o) => !o.isExternal) || nativeMuxed.isNotEmpty;
  }

  bool _isEmbySubtitleActive(EmbySubtitleOption option, SubtitleTrack? cur) {
    if (_pendingEmbySubtitleId == option.selectionId) return true;
    if (_activeEmbySubtitleId == option.selectionId) return true;
    if (cur == null) return false;
    if (option.isExternal) {
      return _subtitleTrackMatchesEmbyOption(cur, option);
    }
    return muxedTrackMatchesEmbyOption(cur, option);
  }

  static Widget _menuSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0x99FFFFFF),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _pickRate(double r) async {
    _notify();
    await _player.setRate(r);
    if (mounted) setState(() {});
  }

  // ── Volume UI ──

  IconData _volumeIcon(double v) {
    if (v <= 0.001) return Icons.volume_off_rounded;
    if (v < 45) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  static const _volumeTrackH = 88.0;
  static const _volumeThumbR = 5.0;
  static const _volumePopH = _volumeTrackH + 20 + 4;

  Widget _buildVolumePopover(double vol) {
    return TapRegion(
      groupId: _volumeTapGroup,
      onTapOutside: (_) => _hideVolumeSlider(),
      child: Material(
        color: const Color(0xE6212121),
        borderRadius: BorderRadius.circular(10),
        elevation: 12,
        shadowColor: Colors.black54,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              _volumeDragging = true;
              _notify();
              _scheduleVolumeHide();
              unawaited(_setVolume(
                  (1 - (e.localPosition.dy / _volumeTrackH)).clamp(0.0, 1.0) *
                      100));
            },
            onPointerMove: (e) {
              if (!_volumeDragging) return;
              _notify();
              _scheduleVolumeHide();
              unawaited(_setVolume(
                  (1 - (e.localPosition.dy / _volumeTrackH)).clamp(0.0, 1.0) *
                      100));
            },
            onPointerUp: (_) {
              _volumeDragging = false;
              _scheduleVolumeHide();
            },
            onPointerCancel: (_) => _volumeDragging = false,
            child: SizedBox(
              width: 36,
              height: _volumeTrackH,
              child: _buildVolumeTrack(vol),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeTrack(double vol) {
    final frac = (vol / 100).clamp(0.0, 1.0);
    final thumbY = frac * _volumeTrackH;
    return Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // Track
          Container(
              width: 3,
              height: _volumeTrackH,
              decoration: BoxDecoration(
                  color: const Color(0x33FFFFFF),
                  borderRadius: BorderRadius.circular(1.5))),
          // Filled
          Positioned(
              bottom: 0,
              child: Container(
                  width: 3,
                  height: thumbY.clamp(0.0, _volumeTrackH),
                  decoration: BoxDecoration(
                      color: const Color(0xE6FFFFFF),
                      borderRadius: BorderRadius.circular(1.5)))),
          // Thumb
          Positioned(
              bottom: (thumbY - _volumeThumbR)
                  .clamp(0.0, _volumeTrackH - _volumeThumbR * 2),
              child: Container(
                  width: _volumeThumbR * 2,
                  height: _volumeThumbR * 2,
                  decoration: const BoxDecoration(
                      color: _foreground, shape: BoxShape.circle))),
        ]);
  }

  // ── Menus ──

  Widget _buildSubtitleMenu(
      {required Tracks tracks, required SubtitleTrack? currentSub}) {
    final switching = _subtitleSwitching;
    if (_isDpad) {
      return TvFocusIconButton(
        icon: Icons.closed_caption_rounded,
        size: _tvBtnSize,
        enabled: !switching,
        color: switching ? _foregroundDim : _foreground,
        onActivate: switching
            ? null
            : () {
                _notify();
                unawaited(_refreshEmbyTrackMap());
                _showTvSubtitlePicker(tracks, currentSub);
              },
        onFocusChange: (focused) {
          if (focused) _notify();
        },
      );
    }

    final emby = widget.embySubtitles;
    final nativeMuxed = _nativeMuxedTracks(tracks, emby);
    final embeddedEmby = uniqueEmbeddedEmbySubtitles(emby);
    final externalEmby = externalEmbySubtitles(emby);
    final showAuto = _showAutoEmbedded(emby, nativeMuxed);
    final indexTracks = _embyIndexTracks ?? const {};
    final fallbackTracks = fallbackEmbyIndexTrackMap(tracks, emby);

    return Theme(
      data: _popupTheme(context),
      child: PopupMenuButton<Object>(
        tooltip: switching ? '字幕切换中…' : '字幕',
        enabled: !switching,
        color: _popupBg,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black54,
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onOpened: () {
          if (_subtitleSwitching) return;
          _notify();
          unawaited(_refreshEmbyTrackMap());
        },
        itemBuilder: (ctx) {
          if (_subtitleSwitching) {
            return [
              PopupMenuItem<Object>(
                enabled: false,
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _foreground.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('字幕切换中…'),
                  ],
                ),
              ),
            ];
          }
          final items = <PopupMenuEntry<Object>>[];
          items.add(PopupMenuItem(
              value: SubtitleTrack.no(),
              child: _popupRow(
                selected: currentSub?.id == 'no' &&
                    !_autoSubtitleActive &&
                    _activeEmbySubtitleId == null,
                label: '关闭字幕',
              )));
          if (showAuto) {
            items.add(PopupMenuItem(
                value: SubtitleTrack.auto(),
                child:
                    _popupRow(selected: _autoSubtitleActive, label: '自动（内嵌）')));
          }
          if (embeddedEmby.isNotEmpty) {
            if (items.isNotEmpty) items.add(const PopupMenuDivider(height: 9));
            items.add(PopupMenuItem<Object>(
              enabled: false,
              child: _menuSectionLabel('内嵌（${embeddedEmby.length}）'),
            ));
            for (final o in embeddedEmby) {
              final sel = _autoSubtitleActive
                  ? false
                  : _isEmbySubtitleActive(o, currentSub);
              final native = indexTracks[o.index] ?? fallbackTracks[o.index];
              items.add(PopupMenuItem(
                  value: o,
                  child: _popupRow(
                    selected: sel,
                    label: embeddedSubtitleMenuLabel(o, native),
                    subtitle: native != null &&
                            o.label != muxedTrackDisplayName(native)
                        ? o.label
                        : null,
                  )));
            }
          } else {
            for (final t in nativeMuxed) {
              items.add(PopupMenuItem(
                  value: t,
                  child: _popupRow(
                    selected: currentSub == t && _activeEmbySubtitleId == null,
                    label: _subtitleMenuLabel(t),
                  )));
            }
          }
          if (externalEmby.isNotEmpty) {
            if (items.isNotEmpty) items.add(const PopupMenuDivider(height: 9));
            items.add(PopupMenuItem<Object>(
              enabled: false,
              child: _menuSectionLabel('外挂（${externalEmby.length}）'),
            ));
            for (final o in externalEmby) {
              final sel = _autoSubtitleActive
                  ? false
                  : _isEmbySubtitleActive(o, currentSub);
              items.add(PopupMenuItem(
                  value: o, child: _popupRow(selected: sel, label: o.label)));
            }
          }
          return items;
        },
        onSelected: _onSubtitleMenuSelected,
        child: _subtitleMenuButton(switching: switching),
      ),
    );
  }

  Widget _subtitleMenuButton({required bool switching}) {
    return SizedBox(
      width: _hitSize,
      height: _hitSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _iconButton(
            icon: Icons.closed_caption_rounded,
            color: switching ? _foregroundDim : null,
          ),
          if (switching)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _foreground.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showTvSubtitlePicker(
    Tracks tracks,
    SubtitleTrack? currentSub,
  ) async {
    final emby = widget.embySubtitles;
    final nativeMuxed = _nativeMuxedTracks(tracks, emby);
    final embeddedEmby = uniqueEmbeddedEmbySubtitles(emby);
    final externalEmby = externalEmbySubtitles(emby);
    final showAuto = _showAutoEmbedded(emby, nativeMuxed);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _popupBg,
        title: const Text('字幕', style: TextStyle(color: _foreground)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TvFocusListTile(
                  title: '关闭字幕',
                  trailing: currentSub?.id == 'no' &&
                          !_autoSubtitleActive &&
                          _activeEmbySubtitleId == null
                      ? Icon(Icons.check, color: _playerAccent(ctx))
                      : null,
                  onActivate: () {
                    Navigator.pop(ctx);
                    _onSubtitleMenuSelected(SubtitleTrack.no());
                  },
                ),
                if (showAuto)
                  TvFocusListTile(
                    title: '自动（内嵌）',
                    trailing: _autoSubtitleActive
                        ? Icon(Icons.check, color: _playerAccent(ctx))
                        : null,
                    onActivate: () {
                      Navigator.pop(ctx);
                      _onSubtitleMenuSelected(SubtitleTrack.auto());
                    },
                  ),
                for (final o in embeddedEmby)
                  TvFocusListTile(
                    title: o.label,
                    onActivate: () {
                      Navigator.pop(ctx);
                      _onSubtitleMenuSelected(o);
                    },
                  ),
                for (final t in nativeMuxed)
                  TvFocusListTile(
                    title: _subtitleMenuLabel(t),
                    onActivate: () {
                      Navigator.pop(ctx);
                      _onSubtitleMenuSelected(t);
                    },
                  ),
                for (final o in externalEmby)
                  TvFocusListTile(
                    title: o.label,
                    onActivate: () {
                      Navigator.pop(ctx);
                      _onSubtitleMenuSelected(o);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioTrackMenu(
      {required Tracks tracks, required AudioTrack? currentAudio}) {
    final list = tracks.audio;
    if (list.length <= 1) return const SizedBox.shrink();
    if (_isDpad) {
      return TvFocusIconButton(
        icon: Icons.audiotrack_rounded,
        size: _tvBtnSize,
        color: _foreground,
        onActivate: () => _showTvAudioPicker(tracks, currentAudio),
        onFocusChange: (focused) {
          if (focused) _notify();
        },
      );
    }
    return Theme(
      data: _popupTheme(context),
      child: PopupMenuButton<AudioTrack>(
        tooltip: '音频',
        color: _popupBg,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black54,
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onOpened: _notify,
        itemBuilder: (ctx) => [
          for (final t in list)
            PopupMenuItem(
                value: t,
                child: _popupRow(
                    selected: currentAudio == t, label: audioTrackLabel(t))),
        ],
        onSelected: (t) async {
          _notify();
          await _player.setAudioTrack(t);
        },
        child: _iconButton(icon: Icons.audiotrack_rounded),
      ),
    );
  }

  // ── Subtitle offset ──

  Future<void> _adjustSubDelay(int deltaMs) async {
    _notify();
    final settings = ref.read(settingsServiceProvider);
    final n = settings.subtitleOffsetMs + deltaMs;
    try {
      await settings.setSubtitleOffsetMs(n);
      await _player.setSubtitleDelay(Duration(milliseconds: n));
    } catch (e, st) {
      AppLog.instance.e(
        'PlayerControls',
        'adjustSubDelay failed deltaMs=$deltaMs',
        error: e,
        stackTrace: st,
      );
    }
  }

  Widget _buildSubOffsetButtons() {
    final settings = ref.watch(settingsServiceProvider);
    final offset = settings.subtitleOffsetMs;

    return Row(mainAxisSize: MainAxisSize.min, children: [
      _miniIconButton(
          Icons.remove_rounded, '提前 0.1s', () => _adjustSubDelay(-100)),
      SizedBox(
        height: _hitSize,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(_fmtOffset(offset),
                style: TextStyle(
                  color: offset != 0 ? _amber : _foregroundDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
        ),
      ),
      _miniIconButton(Icons.add_rounded, '延后 0.1s', () => _adjustSubDelay(100)),
      if (!_isDpad)
        IconButton(
          style: _iconStyle,
          tooltip: '精确调节',
          icon: const Icon(Icons.timer_outlined, size: 20),
          color: _foreground,
          onPressed: _showSubtitleOffsetDialog,
        )
      else
        _transportBtn(
          icon: Icons.timer_outlined,
          tooltip: '精确调节',
          iconSize: 18,
          onPressed: _showSubtitleOffsetDialog,
        ),
    ]);
  }

  void _showSubtitleOffsetDialog() {
    _notify();
    final settings = ref.read(settingsServiceProvider);
    var cur = settings.subtitleOffsetMs;
    showDialog<void>(
        context: context,
        builder: (ctx) {
          var dialogAlive = true;
          return StatefulBuilder(builder: (ctx, setDiag) {
            void safeSetDiag(VoidCallback fn) {
              if (dialogAlive && ctx.mounted) setDiag(fn);
            }

            final accent = _playerAccent(ctx);
            return AlertDialog(
              backgroundColor: _popupBg,
              title: const Text('字幕偏移',
                  style: TextStyle(color: _foreground, fontSize: 16)),
              content: SizedBox(
                  width: 320,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_fmtOffset(cur),
                        style: const TextStyle(
                            color: _foreground,
                            fontSize: 20,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    Slider(
                        value: cur.toDouble(),
                        min: -5000,
                        max: 5000,
                        divisions: 100,
                        label: _fmtOffset(cur),
                        activeColor: accent,
                        onChanged: (v) => safeSetDiag(() => cur = v.round()),
                        onChangeEnd: (v) async {
                          final r = v.round();
                          await settings.setSubtitleOffsetMs(r);
                          try {
                            await _player
                                .setSubtitleDelay(Duration(milliseconds: r));
                          } catch (_) {}
                        }),
                    const SizedBox(height: 8),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                              onPressed: () async {
                                safeSetDiag(() => cur = 0);
                                await settings.setSubtitleOffsetMs(0);
                                try {
                                  await _player.setSubtitleDelay(Duration.zero);
                                } catch (_) {}
                              },
                              child: const Text('重置',
                                  style: TextStyle(color: _foregroundDim))),
                          Text('范围: -5.0s ~ +5.0s',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 12)),
                        ]),
                  ])),
              actions: [
                TextButton(
                    onPressed: () {
                      dialogAlive = false;
                      Navigator.of(ctx).pop();
                    },
                    child:
                        const Text('完成', style: TextStyle(color: _foreground)))
              ],
            );
          });
        });
  }

  // ── Reusable icon buttons ──

  static const _iconStyle = ButtonStyle(
    padding: WidgetStatePropertyAll(EdgeInsets.zero),
    minimumSize: WidgetStatePropertyAll(Size(_hitSize, _hitSize)),
    maximumSize: WidgetStatePropertyAll(Size(_hitSize, _hitSize)),
    iconSize: WidgetStatePropertyAll(_iconSize),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: NoSplash.splashFactory,
  );

  static const _compactIconStyle = ButtonStyle(
    padding: WidgetStatePropertyAll(EdgeInsets.zero),
    minimumSize: WidgetStatePropertyAll(Size(_hitSize, _hitSize)),
    maximumSize: WidgetStatePropertyAll(Size(_hitSize, _hitSize)),
    iconSize: WidgetStatePropertyAll(_iconSize),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: NoSplash.splashFactory,
  );

  Widget _iconButton({required IconData icon, Color? color}) {
    return SizedBox(
      width: _hitSize,
      height: _hitSize,
      child: Center(
        child: Icon(icon, color: color ?? _foreground, size: _iconSize),
      ),
    );
  }

  Widget _miniIconButton(IconData icon, String tooltip, VoidCallback onTap) {
    if (_isDpad) {
      return TvFocusIconButton(
        icon: icon,
        size: _tvBtnSize,
        iconSize: 18,
        color: _foreground,
        onActivate: onTap,
        onFocusChange: (focused) {
          if (focused) _notify();
        },
      );
    }
    return SizedBox(
      width: 32,
      height: _hitSize,
      child: IconButton(
        style: _iconStyle,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 20),
        color: _foreground,
        onPressed: onTap,
      ),
    );
  }

  Widget _buildCompactMoreButton(
    BuildContext context,
    Color accent,
    Tracks tracks,
    SubtitleTrack? currentSub,
    AudioTrack? currentAudio,
    double rate,
  ) {
    return Theme(
      data: _popupTheme(context),
      child: PopupMenuButton<String>(
        tooltip: '更多',
        color: _popupBg,
        icon: const Icon(Icons.more_vert, color: _foreground, size: _iconSize),
        onOpened: _notify,
        itemBuilder: (ctx) => [
          for (final r in _playbackRates)
            PopupMenuItem(
              value: 'rate:$r',
              child: _popupRow(
                  selected: (r - rate).abs() < 0.001,
                  label: '倍速 ${_fmtRate(r)}'),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(
              value: 'audio',
              child: Text('音轨', style: TextStyle(color: _foreground))),
          const PopupMenuItem(
              value: 'subtitle',
              child: Text('字幕', style: TextStyle(color: _foreground))),
          const PopupMenuItem(
              value: 'suboffset',
              child: Text('字幕偏移', style: TextStyle(color: _foreground))),
        ],
        onSelected: (value) {
          if (value.startsWith('rate:')) {
            _pickRate(double.parse(value.substring(5)));
          } else if (value == 'audio') {
            _showAudioTrackPicker(tracks, currentAudio);
          } else if (value == 'subtitle') {
            _showSubtitlePicker(tracks, currentSub);
          } else if (value == 'suboffset') {
            _showSubtitleOffsetDialog();
          }
        },
      ),
    );
  }

  Future<void> _showTvAudioPicker(
    Tracks tracks,
    AudioTrack? currentAudio,
  ) async {
    _notify();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _popupBg,
        title: const Text('音轨', style: TextStyle(color: _foreground)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a
                  in tracks.audio.where((t) => t.id != 'auto' && t.id != 'no'))
                TvFocusListTile(
                  title: audioTrackLabel(a),
                  trailing: currentAudio?.id == a.id
                      ? Icon(Icons.check, color: _playerAccent(ctx))
                      : null,
                  onActivate: () async {
                    Navigator.pop(ctx);
                    await _player.setAudioTrack(a);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAudioTrackPicker(Tracks tracks, AudioTrack? currentAudio) {
    _notify();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _popupBg,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a
                in tracks.audio.where((t) => t.id != 'auto' && t.id != 'no'))
              ListTile(
                title: Text(a.title ?? a.language ?? a.id,
                    style: const TextStyle(color: _foreground)),
                trailing: currentAudio?.id == a.id
                    ? Icon(Icons.check, color: _playerAccent(context))
                    : null,
                onTap: () {
                  _player.setAudioTrack(a);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showSubtitlePicker(Tracks tracks, SubtitleTrack? currentSub) {
    _notify();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _popupBg,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('关闭字幕', style: TextStyle(color: _foreground)),
                onTap: () {
                  _player.setSubtitleTrack(SubtitleTrack.no());
                  Navigator.pop(ctx);
                },
              ),
              for (final s in tracks.subtitle
                  .where((t) => t.id != 'auto' && t.id != 'no'))
                ListTile(
                  title: Text(s.title ?? s.language ?? s.id,
                      style: const TextStyle(color: _foreground)),
                  trailing: currentSub?.id == s.id
                      ? Icon(Icons.check, color: _playerAccent(context))
                      : null,
                  onTap: () {
                    _player.setSubtitleTrack(s);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact mobile layout.
  /// Portrait: center transport + right "more" menu (buttons fold into menu).
  /// Landscape: full 3-column layout — all controls visible directly.
  Widget _buildCompactTransportRow({
    required Color playFill,
    required Color playOn,
    required Color menuAccent,
    required bool playing,
    required Tracks tracks,
    required SubtitleTrack? currentSub,
    required AudioTrack? currentAudio,
    required double rate,
    required double vol,
  }) {
    final landscape = widget.isFullScreen;

    // ── Shared transport buttons (centered group) ──
    Widget transportGroup() {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        if (widget.showEpisodeControls)
          _compactIconBtn(
              Icons.skip_previous_rounded,
              '上一集',
              widget.hasPreviousEpisode ? _foreground : _foregroundDim,
              widget.hasPreviousEpisode
                  ? () {
                      _notify();
                      widget.onPreviousEpisode?.call();
                    }
                  : null),
        _spacer(_btnSpacing),
        _compactIconBtn(Icons.replay_10_rounded, '后退 10 秒', _foreground,
            () => _seekRelative(-10)),
        _spacer(_btnSpacing),
        _playButton(playFill, playOn, playing),
        _spacer(_btnSpacing),
        _compactIconBtn(Icons.forward_10_rounded, '前进 10 秒', _foreground,
            () => _seekRelative(10)),
        _spacer(_btnSpacing),
        if (widget.showEpisodeControls)
          _compactIconBtn(
              Icons.skip_next_rounded,
              '下一集',
              widget.hasNextEpisode ? _foreground : _foregroundDim,
              widget.hasNextEpisode
                  ? () {
                      _notify();
                      widget.onNextEpisode?.call();
                    }
                  : null),
      ]);
    }

    // ── Landscape: full 3-column layout ──
    if (landscape) {
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Left group — same weight as right for centering
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _compactIconBtn(
                  _volumeIcon(vol), '音量', _foreground, _toggleVolumeSlider),
              _spacer(_groupSpacing),
              _buildLandscapeRateMenu(rate),
              _spacer(_groupSpacing),
              _compactIconBtn(Icons.closed_caption_rounded, '字幕', _foreground,
                  () {
                _notify();
                _showSubtitlePicker(tracks, currentSub);
              }),
            ]),
          ),
        ),
        // Center — transport controls (intrinsically centered)
        transportGroup(),
        // Right group — same weight as left for centering
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _compactIconBtn(Icons.audiotrack_rounded, '音轨', _foreground, () {
                _notify();
                _showAudioTrackPicker(tracks, currentAudio);
              }),
              _spacer(_groupSpacing),
              _buildSubOffsetSmallRow(),
              _spacer(_groupSpacing),
              if (widget.showEpisodeControls &&
                  widget.onToggleEpisodeList != null)
                _compactIconBtn(
                  widget.episodeListOpen
                      ? Icons.playlist_play_rounded
                      : Icons.playlist_play_outlined,
                  '选集',
                  widget.episodeListOpen ? menuAccent : _foreground,
                  () {
                    _deferEpisodeListToggle();
                  },
                ),
              if (widget.showEpisodeControls &&
                  widget.onToggleEpisodeList != null)
                _spacer(_groupSpacing),
              if (widget.onToggleFullScreen != null)
                _compactIconBtn(
                  widget.isFullScreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  widget.isFullScreen ? '退出全屏' : '全屏',
                  _foreground,
                  () {
                    _notify();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) widget.onToggleFullScreen!();
                    });
                  },
                ),
            ]),
          ),
        ),
      ]);
    }

    // ── Portrait: compact with "more" menu ──
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: Align(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: transportGroup(),
          ),
        ),
      ),
      if (widget.showEpisodeControls && widget.onToggleEpisodeList != null)
        _compactIconBtn(
          widget.episodeListOpen
              ? Icons.playlist_play_rounded
              : Icons.playlist_play_outlined,
          '选集',
          widget.episodeListOpen ? menuAccent : _foreground,
          () {
            _deferEpisodeListToggle();
          },
        ),
      if (widget.onToggleFullScreen != null)
        _compactIconBtn(
          widget.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
          widget.isFullScreen ? '退出全屏' : '全屏',
          _foreground,
          () {
            _notify();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) widget.onToggleFullScreen!();
            });
          },
        ),
      _buildCompactMoreButton(
          context, menuAccent, tracks, currentSub, currentAudio, rate),
    ]);
  }

  // ── Compact helpers ──

  Widget _spacer(double w) => SizedBox(width: w);

  Widget _playButton(Color fill, Color onFill, bool playing) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: AppRadius.smR,
      ),
      child: IconButton(
        style: IconButton.styleFrom(
          iconSize: 24,
          foregroundColor: onFill,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        tooltip: playing ? '暂停' : '播放',
        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        onPressed: () {
          _notify();
          playing ? _player.pause() : _player.play();
        },
      ),
    );
  }

  Widget _compactIconBtn(
      IconData icon, String tooltip, Color color, VoidCallback? onPressed) {
    return SizedBox(
      width: _hitSize,
      height: _hitSize,
      child: IconButton(
        style: _compactIconStyle,
        tooltip: tooltip,
        icon: Icon(icon, size: _iconSize),
        color: color,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildSubOffsetSmallRow() {
    final settings = ref.watch(settingsServiceProvider);
    final offset = settings.subtitleOffsetMs;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _miniCompactBtn(
          Icons.remove_rounded, '提前 0.1s', () => _adjustSubDelay(-100)),
      _spacer(1),
      SizedBox(
        height: _hitSize,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              _fmtOffset(offset),
              style: TextStyle(
                color: offset != 0 ? _amber : _foregroundDim,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
      _spacer(1),
      _miniCompactBtn(Icons.add_rounded, '延后 0.1s', () => unawaited(_adjustSubDelay(100))),
    ]);
  }

  Widget _miniCompactBtn(
      IconData icon, String tooltip, VoidCallback onPressed) {
    return SizedBox(
      width: 28,
      height: _hitSize,
      child: IconButton(
        style: _compactIconStyle,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18),
        color: _foreground,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildLandscapeRateMenu(double rate) {
    return Theme(
      data: _popupTheme(context),
      child: PopupMenuButton<double>(
        tooltip: '倍速',
        color: _popupBg,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black54,
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        offset: const Offset(0, -8),
        onOpened: _notify,
        itemBuilder: (ctx) => [
          for (final r in _playbackRates)
            PopupMenuItem(
                value: r,
                child: _popupRow(
                    selected: (r - rate).abs() < 0.001, label: _fmtRate(r))),
        ],
        onSelected: _pickRate,
        child: SizedBox(
          width: _hitSize,
          height: _hitSize,
          child: Center(
            child: Text(_fmtRate(rate),
                style: const TextStyle(
                    color: _foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }

  Widget _buildTvTransportRow({
    required Color playFill,
    required Color playOn,
    required Color menuAccent,
    required bool playing,
    required Tracks tracks,
    required SubtitleTrack? currentSub,
    required AudioTrack? currentAudio,
    required double rate,
    required double vol,
  }) {
    final transport = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showEpisodeControls)
          _transportBtn(
            icon: Icons.skip_previous_rounded,
            tooltip: '上一集',
            color: widget.hasPreviousEpisode ? _foreground : _foregroundDim,
            onPressed: widget.hasPreviousEpisode
                ? () {
                    _notify();
                    widget.onPreviousEpisode?.call();
                  }
                : null,
          ),
        _spacer(_btnSpacing),
        _transportBtn(
          icon: Icons.replay_10_rounded,
          tooltip: '后退 10 秒',
          onPressed: () => _seekRelative(-10),
        ),
        _spacer(_btnSpacing),
        _transportBtn(
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: playing ? '暂停' : '播放',
          filled: true,
          fillColor: playFill,
          filledIconColor: playOn,
          iconSize: 22,
          size: 38,
          onPressed: () {
            _notify();
            playing ? _player.pause() : _player.play();
          },
        ),
        _spacer(_btnSpacing),
        _transportBtn(
          icon: Icons.forward_10_rounded,
          tooltip: '前进 10 秒',
          onPressed: () => _seekRelative(10),
        ),
        _spacer(_btnSpacing),
        if (widget.showEpisodeControls)
          _transportBtn(
            icon: Icons.skip_next_rounded,
            tooltip: '下一集',
            color: widget.hasNextEpisode ? _foreground : _foregroundDim,
            onPressed: widget.hasNextEpisode
                ? () {
                    _notify();
                    widget.onNextEpisode?.call();
                  }
                : null,
          ),
      ],
    );

    final tools = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _transportBtn(
            icon: _volumeIcon(vol),
            tooltip: '音量',
            onPressed: _toggleVolumeSlider,
          ),
          _spacer(_groupSpacing),
          _transportRateBtn(rate),
          _spacer(_groupSpacing),
          _buildAudioTrackMenu(tracks: tracks, currentAudio: currentAudio),
          _buildSubtitleMenu(tracks: tracks, currentSub: currentSub),
          _buildSubOffsetButtons(),
          if (widget.showEpisodeControls && widget.onToggleEpisodeList != null) ...[
            _spacer(_groupSpacing),
            _transportBtn(
              icon: widget.episodeListOpen
                  ? Icons.playlist_play_rounded
                  : Icons.playlist_play_outlined,
              tooltip: '选集',
              color: widget.episodeListOpen ? menuAccent : _foreground,
              onPressed: _deferEpisodeListToggle,
            ),
          ],
          if (widget.onToggleFullScreen != null) ...[
            _spacer(_groupSpacing),
            _transportBtn(
              icon: widget.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              tooltip: widget.isFullScreen ? '退出全屏' : '全屏',
              onPressed: () {
                _notify();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) widget.onToggleFullScreen!();
                });
              },
            ),
          ],
        ],
      ),
    );

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: transport),
          const SizedBox(height: 6),
          tools,
        ],
      ),
    );
  }

  Widget _buildFullTransportRow({
    required Color playFill,
    required Color playOn,
    required Color menuAccent,
    required bool playing,
    required Tracks tracks,
    required SubtitleTrack? currentSub,
    required AudioTrack? currentAudio,
    required double rate,
    required double vol,
  }) {
    if (_isDpad) {
      return _buildTvTransportRow(
        playFill: playFill,
        playOn: playOn,
        menuAccent: menuAccent,
        playing: playing,
        tracks: tracks,
        currentSub: currentSub,
        currentAudio: currentAudio,
        rate: rate,
        vol: vol,
      );
    }

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _transportBtn(
                  icon: _volumeIcon(vol),
                  tooltip: '音量',
                  onPressed: _toggleVolumeSlider,
                ),
                _spacer(_groupSpacing),
                _transportRateBtn(rate),
              ],
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showEpisodeControls)
              _transportBtn(
                icon: Icons.skip_previous_rounded,
                tooltip: '上一集',
                color: widget.hasPreviousEpisode ? _foreground : _foregroundDim,
                onPressed: widget.hasPreviousEpisode
                    ? () {
                        _notify();
                        widget.onPreviousEpisode?.call();
                      }
                    : null,
              ),
            _spacer(_btnSpacing),
            _transportBtn(
              icon: Icons.replay_10_rounded,
              tooltip: '后退 10 秒',
              onPressed: () => _seekRelative(-10),
            ),
            _spacer(_btnSpacing),
            _transportBtn(
              icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              tooltip: playing ? '暂停' : '播放',
              filled: true,
              fillColor: playFill,
              filledIconColor: playOn,
              iconSize: 24,
              onPressed: () {
                _notify();
                playing ? _player.pause() : _player.play();
              },
            ),
            _spacer(_btnSpacing),
            _transportBtn(
              icon: Icons.forward_10_rounded,
              tooltip: '前进 10 秒',
              onPressed: () => _seekRelative(10),
            ),
            _spacer(_btnSpacing),
            if (widget.showEpisodeControls)
              _transportBtn(
                icon: Icons.skip_next_rounded,
                tooltip: '下一集',
                color: widget.hasNextEpisode ? _foreground : _foregroundDim,
                onPressed: widget.hasNextEpisode
                    ? () {
                        _notify();
                        widget.onNextEpisode?.call();
                      }
                    : null,
              ),
          ],
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAudioTrackMenu(
                  tracks: tracks,
                  currentAudio: currentAudio,
                ),
                _buildSubtitleMenu(tracks: tracks, currentSub: currentSub),
                _buildSubOffsetButtons(),
                if (widget.showEpisodeControls &&
                    widget.onToggleEpisodeList != null)
                  _transportBtn(
                    icon: widget.episodeListOpen
                        ? Icons.playlist_play_rounded
                        : Icons.playlist_play_outlined,
                    tooltip: '选集',
                    color: widget.episodeListOpen ? menuAccent : _foreground,
                    onPressed: _deferEpisodeListToggle,
                  ),
                if (widget.onToggleFullScreen != null)
                  _transportBtn(
                    icon: widget.isFullScreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    tooltip: widget.isFullScreen ? '退出全屏' : '全屏',
                    onPressed: () {
                      _notify();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) widget.onToggleFullScreen!();
                      });
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );

    return row;
  }

  // ── Main build ──

  @override
  Widget build(BuildContext context) {
    final palette = context.playerColors;
    final playFill = context.appColors.playAction;
    final playOn = context.appColors.onPlayAction;
    final progressColor = palette.progressActive;
    final menuAccent = palette.accent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Volume popover
        if (_volumeSliderVisible)
          SizedBox(
            height: _volumePopH,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.only(left: _barPadding.left - 2),
                child: StreamBuilder<void>(
                  stream: _playerStateStream,
                  builder: (_, __) => _buildVolumePopover(_player.state.volume),
                ),
              ),
            ),
          ),
        // Main control bar
        Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: (_) => _notify(),
          child: DecoratedBox(
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
                child: StreamBuilder<void>(
                  stream: _playerStateStream,
                  builder: (context, _) {
                    final pos = _player.state.position;
                    final dur = _player.state.duration;
                    final maxMs =
                        dur.inMilliseconds <= 0 ? 1 : dur.inMilliseconds;
                    final progress =
                        (pos.inMilliseconds / maxMs).clamp(0.0, 1.0);
                    final vol = _player.state.volume;
                    final rate = _player.state.rate;
                    final tracks = _player.state.tracks;
                    final currentSub = _player.state.track.subtitle;
                    final playing = _player.state.playing;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildTimelineWithGesturePreview(
                          context,
                          progressColor,
                          menuAccent,
                          pos,
                          dur,
                          maxMs,
                          progress,
                        ),
                        const SizedBox(height: 6),
                        if (_isDpad && !widget.compact)
                          _buildFullTransportRow(
                            playFill: playFill,
                            playOn: playOn,
                            menuAccent: menuAccent,
                            playing: playing,
                            tracks: tracks,
                            currentSub: currentSub,
                            currentAudio: _player.state.track.audio,
                            rate: rate,
                            vol: vol,
                          )
                        else
                          SizedBox(
                            height: _hitSize,
                            child: widget.compact
                                ? _buildCompactTransportRow(
                                    playFill: playFill,
                                    playOn: playOn,
                                    menuAccent: menuAccent,
                                    playing: playing,
                                    tracks: tracks,
                                    currentSub: currentSub,
                                    currentAudio: _player.state.track.audio,
                                    rate: rate,
                                    vol: vol,
                                  )
                                : _buildFullTransportRow(
                                    playFill: playFill,
                                    playOn: playOn,
                                    menuAccent: menuAccent,
                                    playing: playing,
                                    tracks: tracks,
                                    currentSub: currentSub,
                                    currentAudio: _player.state.track.audio,
                                    rate: rate,
                                    vol: vol,
                                  ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Timeline ──

  Widget _buildTimelineWithGesturePreview(
    BuildContext context,
    Color progressColor,
    Color previewHighlight,
    Duration pos,
    Duration dur,
    int maxMs,
    double progress,
  ) {
    final preview = widget.gestureSeekPreviewSeconds;
    if (preview == null) {
      return _buildTimeline(
        context,
        progressColor,
        previewHighlight,
        pos,
        dur,
        maxMs,
        progress,
        0,
      );
    }
    return ValueListenableBuilder<int>(
      valueListenable: preview,
      builder: (context, previewSec, _) {
        return _buildTimeline(
          context,
          progressColor,
          previewHighlight,
          pos,
          dur,
          maxMs,
          progress,
          previewSec,
        );
      },
    );
  }

  Widget _buildTimeline(
    BuildContext context,
    Color progressColor,
    Color previewHighlight,
    Duration pos,
    Duration dur,
    int maxMs,
    double progress,
    int gesturePreviewSeconds,
  ) {
    Duration displayPos = pos;
    var displayProgress = progress;
    final dragging = _timelineDragValue != null;
    if (dragging) {
      displayProgress = _timelineDragValue!;
      displayPos = Duration(
        milliseconds: (_timelineDragValue! * maxMs).round().clamp(0, maxMs),
      );
    } else if (gesturePreviewSeconds != 0 && maxMs > 1) {
      final targetMs =
          (pos.inMilliseconds + gesturePreviewSeconds * 1000).clamp(0, maxMs);
      displayPos = Duration(milliseconds: targetMs);
      displayProgress = targetMs / maxMs;
    }
    final previewing = dragging || gesturePreviewSeconds != 0;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SizedBox(
        width: 72,
        child: Text(_fmtHms(displayPos),
            style: TextStyle(
              color: previewing ? previewHighlight : _foregroundDim,
              fontSize: 11.5,
              fontWeight: previewing ? FontWeight.w600 : FontWeight.normal,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ),
      Expanded(
        child: LayoutBuilder(builder: (ctx, c) {
          final w = c.maxWidth;
          const tipHalf = 30.0;
          final hf = _timelineHoverFraction;
          Duration? hoverDur;
          if (hf != null) {
            hoverDur =
                Duration(milliseconds: (hf * maxMs).round().clamp(0, maxMs));
          }
          final tipFraction = _timelineDragValue ?? hf;
          Duration? tipDur;
          if (dragging) {
            tipDur = displayPos;
          } else if (hoverDur != null) {
            tipDur = hoverDur;
          }
          final displayVal = displayProgress;
          return SizedBox(
            height: 28,
            child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Background track
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
                  // Filled track
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: displayVal.clamp(0.0, 1.0),
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: progressColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Thumb indicator
                  Positioned(
                    left: ((displayVal * w) - 4).clamp(0.0, w - 8),
                    child: IgnorePointer(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: progressColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: progressColor.withValues(alpha: 0.45),
                                  blurRadius: 4)
                            ]),
                      ),
                    ),
                  ),
                  // Interactive slider (invisible)
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
                        setState(() =>
                            _timelineDragValue = (dx / w).clamp(0.0, 1.0));
                      },
                      onHorizontalDragEnd: (_) {
                        final v = _timelineDragValue;
                        if (v != null) {
                          _notify();
                          widget.onSeek?.call();
                          _player.seek(
                              Duration(milliseconds: (v * maxMs).round()));
                          setState(() => _timelineDragValue = null);
                        }
                      },
                      onHorizontalDragCancel: () {
                        if (_timelineDragValue != null) {
                          setState(() => _timelineDragValue = null);
                        }
                      },
                      onTapDown: (d) {
                        _notify();
                        widget.onSeek?.call();
                        final x = d.localPosition.dx;
                        _player.seek(Duration(
                            milliseconds:
                                ((x / w) * maxMs).round().clamp(0, maxMs)));
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // Drag / hover time tooltip
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
                ]),
          );
        }),
      ),
      SizedBox(
        width: 72,
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(_fmtHms(dur),
              style: const TextStyle(
                  color: _foregroundDim,
                  fontSize: 11.5,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ),
      ),
    ]);
  }
}
