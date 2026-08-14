import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';

// ignore: implementation_imports
import 'package:media_kit/src/player/native/player/real.dart' as native;

import '../logging/app_log.dart';
import 'subtitle_emby_index.dart';
import 'subtitle_render_mode.dart';
import 'subtitle_track_kind.dart';

final _subtitleMpvConfiguredExpando = Expando<bool>();
final _lastSubtitleRenderModeExpando = Expando<SubtitleRenderMode>();
final _mpvHadExternalSubtitleExpando = Expando<bool>();

/// Muxed / external subtitle switching via mpv commands (avoids [Player.setSubtitleTrack] lock).
extension PlayerSubtitleVisibility on Player {
  native.NativePlayer? get _native =>
      platform is native.NativePlayer ? platform as native.NativePlayer : null;

  Future<void> configureMpvSubtitlesOnce() async {
    if (kIsWeb) return;
    final platform = _native;
    if (platform == null) return;

    if (_subtitleMpvConfiguredExpando[this] != null) return;
    _subtitleMpvConfiguredExpando[this] = true;

    Future<void> set(String name, String value) =>
        platform.setProperty(name, value, waitForInitialization: false);

    await set('blend-subtitles', 'yes');
    await set('stretch-image-subs', 'yes');
  }

  Future<void> applySubtitleRenderMode(SubtitleTrack track) async {
    if (kIsWeb) return;
    final platform = _native;
    if (platform == null) return;

    await configureMpvSubtitlesOnce();

    final mode = subtitleRenderModeForTrack(track);
    if (_lastSubtitleRenderModeExpando[this] == mode) return;
    _lastSubtitleRenderModeExpando[this] = mode;

    Future<void> set(String name, String value) =>
        platform.setProperty(name, value, waitForInitialization: false);

    switch (mode) {
      case SubtitleRenderMode.flutterOverlay:
        await set('sub-ass', 'no');
        await set('blend-subtitles', 'no');
        // Native mpv rendering off — the Flutter [SubtitleView] overlay (fed
        // from mpv `sub-text`, which stays populated regardless of
        // sub-visibility) is the only renderer. Keeping sub-visibility=yes
        // would draw the SRT twice (mpv + overlay).
        await set('sub-visibility', 'no');
        await set('secondary-sub-visibility', 'no');
        await set('sub-auto', 'no');
      case SubtitleRenderMode.mpvLibass:
      case SubtitleRenderMode.mpvBitmap:
        await set('sub-ass', 'yes');
        await set('blend-subtitles', 'yes');
        await set('sub-visibility', 'yes');
        await set('secondary-sub-visibility', 'no');
        await set('sub-auto', 'no');
      case SubtitleRenderMode.off:
        await set('sub-visibility', 'no');
        await set('secondary-sub-visibility', 'no');
    }

    // Toggling `sub-ass` / `blend-subtitles` makes mpv reinitialize the sub
    // renderer / video output asynchronously. A `sid` written right after can
    // be clobbered by that reconfig (e.g. the first PGS switch from a muxed
    // text overlay would silently fail and need a second try). Let it settle
    // before the caller selects the track.
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  Future<void> _mpvSetSid(String sid) async {
    final platform = _native;
    if (platform == null) return;
    await platform.command(['set', 'sid', sid], waitForInitialization: false);
  }

  /// Re-seeks to [posBeforeSid] after a muxed subtitle switch — but only when
  /// the captured position is a plausible mid-file value.
  ///
  /// On strm-over-CDN MKV, mpv's demuxer can momentarily report the bogus
  /// "position ≈ duration" (SeekHead byte-range fail on a cold cache). Writing
  /// that back as `time-pos` turns the subtitle switch into a seek-to-EOF,
  /// which stops playback and is unrecoverable. Guarding the write keeps the
  /// switch from ever becoming an EOF seek.
  Future<void> _restorePositionAfterSubtitleSwitch(String? posBeforeSid) async {
    if (posBeforeSid == null || posBeforeSid.isEmpty || posBeforeSid == '0') {
      return;
    }
    final platform = _native;
    if (platform == null) return;

    final double value;
    try {
      value = double.parse(posBeforeSid);
    } catch (_) {
      return;
    }
    if (value <= 0) return;

    final durMs = state.duration.inMilliseconds;
    final valueMs = (value * 1000).round();
    // With a known duration, skip near-end positions — that is the MKV
    // SeekHead artifact, not where playback actually is.
    if (durMs > 30000 &&
        (valueMs >= durMs - 15000 || valueMs >= durMs * 0.98)) {
      AppLog.instance.w(
        'Subtitle',
        'skip time-pos restore: captured pos=${valueMs}ms looks like the '
            'bogus EOF position (dur=${durMs}ms) — not re-seeking',
      );
      return;
    }

    try {
      await platform.setProperty(
        'time-pos',
        (value + 0.001).toStringAsFixed(6),
        waitForInitialization: false,
      );
    } catch (_) {}
  }

  Future<void> _mpvSubAdd(String uri, SubtitleTrack track) async {
    final platform = _native;
    if (platform == null) return;
    await platform.command(
      [
        'sub-add',
        uri,
        'select',
        track.title ?? 'external',
        track.language ?? 'auto',
      ],
      waitForInitialization: false,
    );
  }

  /// mpv still has `sub-add` tracks. Avoids `track-list` unless we know externals were used.
  Future<bool> needsMpvExternalCleanup() async {
    if (!_currentTrackIsExternal && _mpvHadExternalSubtitleExpando[this] != true) {
      return false;
    }
    final ids = await mpvExternalSubtitleIds(this);
    if (ids.isEmpty) {
      _mpvHadExternalSubtitleExpando[this] = false;
      return false;
    }
    return true;
  }

  bool get _currentTrackIsExternal {
    final cur = state.track.subtitle;
    if (cur.id == 'no' || cur.id == 'auto') return false;
    if (cur.uri || cur.data) return true;
    final id = cur.id;
    return id.startsWith('http://') ||
        id.startsWith('https://') ||
        id.startsWith('file://');
  }

  /// Removes Emby/mpv external subs added via `sub-add` (required before muxed `sid`).
  Future<void> clearExternalSubtitles() async {
    if (kIsWeb) return;
    final platform = _native;
    if (platform == null) return;

    var removed = 0;

    final externalIds = await mpvExternalSubtitleIds(this);
    for (final id in externalIds) {
      try {
        await platform.command(['sub-remove', id], waitForInitialization: false);
        removed++;
      } catch (_) {}
    }

    if (removed == 0) {
      for (var i = 0; i < 2; i++) {
        try {
          await platform.command(['sub-remove', 'select'], waitForInitialization: false);
          removed++;
        } catch (_) {}
      }
    }

    for (final t in state.tracks.subtitle) {
      if (t.uri || t.data) {
        try {
          await platform.command(['sub-remove', t.id], waitForInitialization: false);
          removed++;
        } catch (_) {}
      } else {
        final id = t.id;
        if (id.startsWith('http://') ||
            id.startsWith('https://') ||
            id.startsWith('file://')) {
          try {
            await platform.command(['sub-remove', id], waitForInitialization: false);
            removed++;
          } catch (_) {}
        }
      }
    }

    if (removed > 0) {
      _mpvHadExternalSubtitleExpando[this] = false;
    }

    // Always deselect the currently-active muxed `sid`. Otherwise switching
    // from an embedded (muxed) subtitle to an external `sub-add` would leave
    // the embedded track selected and render both at the same time (multiple
    // subtitle lines on screen). Writing `sid=no` also drives media_kit's
    // track state, unmounting the Flutter text overlay if one is mounted.
    try {
      await platform.setProperty('sid', 'no', waitForInitialization: false);
    } catch (_) {}
    invalidateMpvSidIndexCache(this);
    await Future<void>.delayed(const Duration(milliseconds: 32));
  }

  /// Muxed text via `sub-ass=no` + Flutter overlay (`sub-text`); avoids libass VO stall on `sid`.
  Future<bool> activateMuxedTextSubtitle(
    SubtitleTrack track, {
    String reason = 'unspecified',
  }) async {
    if (kIsWeb) return false;
    if (!isTextMuxedSubtitle(track)) return false;

    if (_currentTrackIsExternal || await needsMpvExternalCleanup()) {
      await clearExternalSubtitles();
    }

    await applySubtitleRenderMode(track);

    final platform = _native;
    if (platform == null) return false;

    late final String? posBeforeSid;
    try {
      posBeforeSid = await platform.getProperty('time-pos', waitForInitialization: false);
    } catch (_) {
      posBeforeSid = null;
    }

    try {
      // Refresh the demuxer/render state at the current position FIRST, then
      // select the track. Writing `time-pos` after `set sid` transiently
      // clobbers the freshly selected sid on a strm-over-CDN MKV (the seek
      // re-reads demuxer state), so the first cross-mode text switch needed a
      // retry to stick. Seek-then-set makes it take on the first attempt.
      await _restorePositionAfterSubtitleSwitch(posBeforeSid);

      await platform.setSubtitleTrack(track, synchronized: false);

      AppLog.instance.d('Subtitle', 'muxed text overlay sid=${track.id} ($reason)');
      return true;
    } catch (e, st) {
      AppLog.instance.e('Subtitle', 'muxed text overlay $reason', error: e, stackTrace: st);
      return false;
    }
  }

  /// Muxed PGS (or non-text): libass texture + `set sid`.
  Future<bool> activateMuxedSubtitle(
    SubtitleTrack track, {
    String reason = 'unspecified',
    bool verifySid = true,
  }) async {
    if (kIsWeb) return false;
    if (isTextMuxedSubtitle(track)) {
      return activateMuxedTextSubtitle(track, reason: reason);
    }

    final platform = _native;
    if (platform == null) return false;

    if (_currentTrackIsExternal || await needsMpvExternalCleanup()) {
      await clearExternalSubtitles();
    }

    await applySubtitleRenderMode(track);

    late final String? posBeforeSid;
    try {
      posBeforeSid = await platform.getProperty('time-pos', waitForInitialization: false);
    } catch (_) {
      posBeforeSid = null;
    }

    await _mpvSetSid(track.id);

    await _restorePositionAfterSubtitleSwitch(posBeforeSid);

    if (!verifySid) return true;

    var sid = await platform.getProperty('sid', waitForInitialization: false);
    if (sid != track.id) {
      // The render-mode reconfig (or the time-pos restore) can transiently
      // reset sid. Retry briefly so the first PGS switch sticks instead of
      // requiring a second manual switch.
      for (var attempt = 0; attempt < 3 && sid != track.id; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await _mpvSetSid(track.id);
        sid = await platform.getProperty('sid', waitForInitialization: false);
      }
    }
    final ok = sid == track.id;
    if (!ok) {
      AppLog.instance.w(
        'Subtitle',
        'muxed activate failed wanted=${track.id} mpvSid=$sid ($reason)',
      );
    }
    return ok;
  }

  Future<bool> activateExternalSubtitleFile(
    SubtitleTrack track, {
    String reason = 'external',
  }) async {
    if (kIsWeb) return false;
    if (!track.uri && !track.data) return false;

    final platform = _native;
    if (platform == null) return false;

    await clearExternalSubtitles();
    await applySubtitleRenderMode(track);

    try {
      await _mpvSubAdd(track.id, track);
    } catch (e, st) {
      AppLog.instance.e('Subtitle', 'sub-add $reason', error: e, stackTrace: st);
      return false;
    }

    for (final delay in const [
      Duration(milliseconds: 16),
      Duration(milliseconds: 80),
      Duration(milliseconds: 200),
      Duration(milliseconds: 500),
    ]) {
      await Future<void>.delayed(delay);
      final current = state.track.subtitle;
      if (externalSubtitleTrackActive(current, track)) {
        _mpvHadExternalSubtitleExpando[this] = true;
        invalidateMpvSidIndexCache(this);
        return true;
      }
      final sid = await mpvSubtitleId();
      if (sid != null && sid != 'no' && sid != 'auto') {
        _mpvHadExternalSubtitleExpando[this] = true;
        invalidateMpvSidIndexCache(this);
        return true;
      }
    }

    AppLog.instance.w('Subtitle', 'external may not be active ($reason)');
    return false;
  }

  Future<bool> activateSubtitleTrack(
    SubtitleTrack track, {
    String reason = 'unspecified',
  }) async {
    if (track.id == 'no') {
      await clearExternalSubtitles();
      await applySubtitleRenderMode(track);
      await _mpvSetSid('no');
      return true;
    }
    if (track.uri || track.data) {
      return activateExternalSubtitleFile(track, reason: reason);
    }
    return activateMuxedSubtitle(track, reason: reason);
  }

  Future<String?> mpvSubtitleId() async {
    final platform = _native;
    if (platform == null) return null;
    try {
      return await platform.getProperty('sid', waitForInitialization: false);
    } catch (_) {
      return null;
    }
  }
}

void resetPlayerSubtitleConfigureCache(Player player) {
  _subtitleMpvConfiguredExpando[player] = null;
  _lastSubtitleRenderModeExpando[player] = null;
  _mpvHadExternalSubtitleExpando[player] = null;
}

/// Whether [current] is the external track we tried to load ([target]).
bool externalSubtitleTrackActive(SubtitleTrack current, SubtitleTrack target) {
  if (current.id == 'no' || current.id == 'auto') return false;
  if (current.id == target.id) return true;
  if (target.uri) {
    if (!current.uri) return false;
    final want = Uri.tryParse(target.id);
    final cur = Uri.tryParse(current.id);
    if (want != null && cur != null) {
      if (want.scheme == cur.scheme &&
          want.host.toLowerCase() == cur.host.toLowerCase() &&
          want.path == cur.path) {
        return true;
      }
    }
    final wantBase = target.id.split('?').first;
    return current.id.startsWith(wantBase) || current.id.contains(wantBase);
  }
  if (target.data) {
    return current.data || current.uri;
  }
  return false;
}
