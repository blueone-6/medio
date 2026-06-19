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
        await set('sub-visibility', 'yes');
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
  }

  Future<void> _mpvSetSid(String sid) async {
    final platform = _native;
    if (platform == null) return;
    await platform.command(['set', 'sid', sid], waitForInitialization: false);
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
      try {
        await platform.setProperty('sid', 'no', waitForInitialization: false);
      } catch (_) {}
      invalidateMpvSidIndexCache(this);
      await Future<void>.delayed(const Duration(milliseconds: 32));
    }
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
      await platform.setSubtitleTrack(track, synchronized: false);

      if (posBeforeSid != null && posBeforeSid.isNotEmpty && posBeforeSid != '0') {
        try {
          await platform.setProperty(
            'time-pos',
            (double.parse(posBeforeSid) + 0.001).toStringAsFixed(6),
            waitForInitialization: false,
          );
        } catch (_) {}
      }

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

    if (posBeforeSid != null && posBeforeSid.isNotEmpty && posBeforeSid != '0') {
      try {
        await platform.setProperty(
          'time-pos',
          (double.parse(posBeforeSid) + 0.001).toStringAsFixed(6),
          waitForInitialization: false,
        );
      } catch (_) {}
    }

    if (!verifySid) return true;

    final sid = await platform.getProperty('sid', waitForInitialization: false);
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
