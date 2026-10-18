/// Recoverable transport-level failures surfaced by the Media3 ExoPlayer
/// bridge that are worth a same-source reopen (the stream URL/CDN may still
/// be fine — the failure was transient).
///
/// Mirrors `player_network_error.dart` (the mpv path) for ExoPlayer's error
/// strings: bridge messages look like `Source error`, `Response code: 503`,
/// `Unable to connect to ...`.
bool isRecoverableExoNetworkError(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('response code: 5')) return true; // 5xx from CDN/origin
  if (lower.contains('response code: 429')) return true; // CDN rate limit
  if (lower.contains('connection reset') ||
      lower.contains('connection aborted') ||
      lower.contains('connection timed out') ||
      lower.contains('network is unreachable') ||
      lower.contains('unable to connect')) {
    return true;
  }
  if (lower.contains('unexpected loader exception')) return true;
  // media3 wraps I/O failures as a bare "Source error".
  if (lower.contains('source error')) return true;
  return false;
}

/// Signed-URL expiry (`403`/`410` from the CDN) needs a full re-bootstrap so
/// the strm/CDN chain is re-resolved, not just a reopen.
bool isExoSignedUrlExpiredError(String text) {
  final lower = text.toLowerCase();
  return lower.contains('response code: 403') ||
      lower.contains('response code: 410') ||
      lower.contains('response code: 401');
}
