/// Backoff schedule for automatic recovery re-opens of a remote stream.
///
/// Production logs (115 CDN direct links) show rapid `stop()` → `open()`
/// cycles tripping the CDN's per-URL connection management: every re-open
/// within ~10s of the previous connection fails fast ("Failed to open"),
/// and playback recovers only once the stale server-side connection
/// expires. Waiting between the stop and the next open lets the CDN tear
/// the old connection down so each attempt lands in a fresh connection
/// window, instead of amplifying a transient glitch into a rapid-fire
/// failure storm (observed: seven opens in ~12s, all refused, success only
/// ~13s after the first failure).
///
/// The first re-open already waits 1s: it both gives the CDN a moment and
/// covers the go-emby2openlist lazy MediaSource resolution, which finishes
/// within ~1-2s of the first PlaybackInfo.
Duration reopenBackoffDelay(int priorReopenFailures) {
  const schedule = [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 10),
  ];
  final index = priorReopenFailures <= 0
      ? 0
      : priorReopenFailures >= schedule.length
          ? schedule.length - 1
          : priorReopenFailures;
  return schedule[index];
}
