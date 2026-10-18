/// Pure decision logic for transparent re-resolution in the netdisk transport.
///
/// The transport calls a `refresh` callback to obtain a fresh signed URL when
/// the current one has expired. Deciding *when* to do that is pure and tested
/// here.
library;

/// HTTP statuses that mean "the signed URL is no longer valid".
bool isExpiryStatus(int? statusCode) =>
    statusCode == 401 || statusCode == 403 || statusCode == 410;

/// Whether the transport should call `refresh()` and retry the current segment.
///
/// [hasSentBytes] guards against splicing two different upstream bodies: once
/// any byte of the segment has reached the client we cannot transparently swap
/// the URL. [connectionFailed] covers resets/timeouts (no status code).
bool shouldReResolve({
  int? statusCode,
  bool connectionFailed = false,
  required bool hasSentBytes,
  required int refreshAttempts,
  int maxRefreshAttempts = 2,
}) {
  if (hasSentBytes) return false;
  if (refreshAttempts >= maxRefreshAttempts) return false;
  return connectionFailed || isExpiryStatus(statusCode);
}

/// Whether an expired upstream should fall back to the per-request redirecting
/// stream URL instead of waiting for `refresh()` to return something fresh.
///
/// A pre-resolved signed CDN URL is minted once and expires (115 CDN: within
/// minutes), while the Emby `/stream` URL 307s to a *fresh* signed URL on every
/// request. The server caches its own redirect for minutes, so a `refresh()`
/// during expiry can keep handing back the same dead URL — retrying through the
/// redirecting URL is what makes recovery fast (a seek instead of a stall).
bool shouldUseRedirectFallback({
  required int? statusCode,
  required bool connectionFailed,
  required String? redirectUrl,
  required String? activeUrl,
}) {
  if (connectionFailed) return false;
  if (!isExpiryStatus(statusCode)) return false;
  if (redirectUrl == null || redirectUrl.isEmpty) return false;
  return redirectUrl != activeUrl;
}

/// Backoff before refresh attempt number [attempt] (1-based).
///
/// Kept short: a fresh URL usually resolves in well under a second, and the
/// player is already waiting on this byte range.
Duration reResolveDelay(int attempt) {
  const schedule = <Duration>[
    Duration(milliseconds: 300),
    Duration(seconds: 1),
  ];
  if (attempt <= 1) return schedule.first;
  final index = attempt - 1;
  return index >= schedule.length ? schedule.last : schedule[index];
}
