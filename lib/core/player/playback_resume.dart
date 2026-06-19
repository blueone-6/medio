/// Merged resume fields from item, UserData API, route hints, and local cache.
class PlaybackResumeHints {
  const PlaybackResumeHints({
    this.playbackPositionTicks,
    this.playedPercentage,
    this.played,
    this.isResumable,
    this.runTimeTicks,
  });

  final int? playbackPositionTicks;
  final double? playedPercentage;
  final bool? played;
  final bool? isResumable;
  final int? runTimeTicks;
}

/// Emby uses 0–100; some payloads use 0–1.
double? normalizePlayedPercentage(double? raw) {
  if (raw == null || raw <= 0) return null;
  if (raw <= 1.0) return raw * 100.0;
  return raw;
}

PlaybackResumeHints mergePlaybackResumeHints({
  int? itemPlaybackPositionTicks,
  double? itemPlayedPercentage,
  bool? itemPlayed,
  int? itemRunTimeTicks,
  Map<String, dynamic>? userData,
  double? routePlayedPercentage,
  int? routePositionTicks,
  int? localPositionTicks,
}) {
  int? ticks = itemPlaybackPositionTicks;
  double? pct = normalizePlayedPercentage(itemPlayedPercentage);
  bool? played = itemPlayed;
  bool? resumable;

  if (userData != null) {
    final ud = userData;
    ticks ??= (ud['PlaybackPositionTicks'] as num?)?.toInt() ??
        (ud['playbackPositionTicks'] as num?)?.toInt();
    pct ??= normalizePlayedPercentage(
      (ud['PlayedPercentage'] as num?)?.toDouble() ??
          (ud['playedPercentage'] as num?)?.toDouble(),
    );
    played ??= ud['Played'] as bool? ?? ud['played'] as bool?;
    final r = ud['IsResumable'] ?? ud['isResumable'];
    if (r is bool) resumable = r;
  }

  for (final candidate in [routePositionTicks, localPositionTicks]) {
    if (candidate == null || candidate <= 0) continue;
    ticks = ticks == null ? candidate : (candidate > ticks ? candidate : ticks);
  }
  pct ??= normalizePlayedPercentage(routePlayedPercentage);

  if (pct == null &&
      ticks != null &&
      ticks > 0 &&
      itemRunTimeTicks != null &&
      itemRunTimeTicks > 0) {
    pct = ticks * 100.0 / itemRunTimeTicks;
  }

  return PlaybackResumeHints(
    playbackPositionTicks: ticks,
    playedPercentage: pct,
    played: played,
    isResumable: resumable,
    runTimeTicks: itemRunTimeTicks,
  );
}

/// Picks the best Emby/local tick value for resume.
int? resolveResumePositionTicks({
  int? embyPlaybackPositionTicks,
  int? localPlaybackPositionTicks,
  double? playedPercentage,
  int? runTimeTicks,
}) {
  int? best;
  final emby = embyPlaybackPositionTicks;
  final local = localPlaybackPositionTicks;
  if (emby != null && emby > 0 && local != null && local > 0) {
    best = emby > local ? emby : local;
  } else {
    best = (emby != null && emby > 0)
        ? emby
        : (local != null && local > 0)
            ? local
            : null;
  }

  if (best != null) return best;

  final pct = normalizePlayedPercentage(playedPercentage);
  final runtime = runTimeTicks;
  if (pct == null || runtime == null || runtime <= 0) {
    return null;
  }
  if (pct >= 99.5) return null;
  return (runtime * pct / 100).round();
}

/// Computes a client seek target from Emby [UserData] playback fields.
Duration? resumePlaybackPosition({
  int? playbackPositionTicks,
  int? runTimeTicks,
  bool? played,
  double? playedPercentage,
  bool? isResumable,
}) {
  if (isResumable == false) return null;

  final pct = normalizePlayedPercentage(playedPercentage);
  final ticks = resolveResumePositionTicks(
    embyPlaybackPositionTicks: playbackPositionTicks,
    playedPercentage: pct,
    runTimeTicks: runTimeTicks,
  );
  if (ticks == null || ticks <= 0) return null;

  // Do not block on [Played] alone — some servers set it while still resumable.
  if (pct != null && pct >= 90 && (playbackPositionTicks == null || playbackPositionTicks <= 0)) {
    return null;
  }

  final position = Duration(microseconds: ticks ~/ 10);
  if (position < const Duration(seconds: 5)) return null;

  if (runTimeTicks != null && runTimeTicks > 0) {
    final runtime = Duration(microseconds: runTimeTicks ~/ 10);
    final remaining = runtime - position;
    if (remaining <= const Duration(seconds: 30)) return null;
  }

  return position;
}

/// True when [pos] is close enough to [resumeAt] to drop the bootstrap loading
/// overlay. mpv often reports a few hundred ms below the `--start` target.
bool isResumePositionSettled(
  Duration pos,
  Duration resumeAt, {
  int toleranceMs = 2000,
}) {
  if (resumeAt <= Duration.zero) {
    return pos.inMilliseconds > 50;
  }
  final drift = pos.inMilliseconds - resumeAt.inMilliseconds;
  return drift >= -toleranceMs && drift <= toleranceMs + 3000;
}

/// True when playback is genuinely near the end (for auto-play-next guards).
bool isPlaybackNearEnd(
  Duration pos,
  Duration dur, {
  Duration endMargin = const Duration(seconds: 15),
  double minFraction = 0.92,
}) {
  if (dur <= Duration.zero) return false;
  if (pos >= dur - endMargin) return true;
  final durMs = dur.inMilliseconds;
  if (durMs <= 0) return false;
  return pos.inMilliseconds / durMs >= minFraction;
}
