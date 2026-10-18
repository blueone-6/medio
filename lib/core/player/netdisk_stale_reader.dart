/// Stale-reader policy for the netdisk transport.
///
/// Field capture (docs/specs/2026-10-18-netdisk-buffering-todo.md) showed a 4K
/// remux streaming through three concurrent localhost connections on the same
/// file: one at the playback position, and two more that Media3 opened while
/// resolving the Matroska seek map (`Range: bytes=0-` and `bytes=7546-`) and
/// then never closed. All three read at full speed for minutes, so the CDN
/// budget — throttled per connection — was split, and the video stream got
/// barely its own bitrate: the player's buffer never rose above ~2.5 s and it
/// rebuffered every ~20 s.
///
/// The transport cannot tell "the player finished with this connection" from
/// "the player is multiplexing two positions", but it can tell that one reader
/// is far away from the newest one and has been for a while: for a progressive
/// remux that is a reader the player has moved away from. Keeping the decision
/// pure makes the rule testable without sockets or timers.
library;

/// Whether [id] should be treated as a reader the player has moved away from.
///
/// [id]/[positionBytes]/[alive]/[wasStale] describe the relay being judged;
/// [newestId]/[newestPositionBytes]/[newestAlive] the most recently opened one.
///
/// A *newly* stale reader is one where a newer reader exists, that newer reader
/// has had time to settle, the judged reader is far from it, and the judged
/// reader has itself been alive long enough not to be a short probe (the
/// Matroska tail and header reads finish in well under a second and must not be
/// throttled). Once a reader has been judged stale it stays stale until it
/// comes back near the newest reader: a seek changes the anchor, and without
/// that hysteresis every abandoned reader would get a fresh grace window in
/// which it pulls at full speed again.
bool isStaleReader({
  required int id,
  required int positionBytes,
  required Duration alive,
  required int newestId,
  required int newestPositionBytes,
  required Duration newestAlive,
  required int minDistanceBytes,
  required Duration minAlive,
  bool wasStale = false,
}) {
  if (id == newestId) return false;
  if (id > newestId) return false;
  final distance = (positionBytes - newestPositionBytes).abs();
  if (distance <= minDistanceBytes) return false;
  if (wasStale) return true;
  if (newestAlive < minAlive) return false;
  if (alive < minAlive) return false;
  return true;
}
