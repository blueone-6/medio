/// Pure byte-range math for the netdisk transport.
///
/// The player (libmpv / ExoPlayer) requests a byte range; the transport fetches
/// it from the CDN in block-aligned chunks so the same bytes can be served from
/// (and written to) the on-disk block cache. Keeping the decisions here pure
/// makes them unit-testable without a socket.
library;

/// A client-requested byte range. [end] is inclusive; null means "to EOF".
class ResolvedRange {
  const ResolvedRange(this.start, this.end);

  final int start;
  final int? end;

  /// Number of bytes covered for a known [total], or null when the range is
  /// open-ended and [total] is unknown.
  int? length(int? total) {
    if (end != null) return end! - start + 1;
    if (total == null) return null;
    return total - start;
  }

  @override
  String toString() => 'ResolvedRange($start, ${end ?? 'EOF'})';
}

final RegExp _bytesRange = RegExp(r'^bytes=(\d*)-(\d*)$');

/// Parses a client `Range` header into an absolute [ResolvedRange].
///
/// Handles `bytes=a-b`, `bytes=a-`, and the suffix form `bytes=-N` (the latter
/// needs [total]); anything unparseable falls back to the whole file.
ResolvedRange resolveRangeRequest(String? rangeHeader, int? total) {
  ResolvedRange wholeFile() =>
      ResolvedRange(0, total == null ? null : total - 1);

  final raw = rangeHeader?.trim();
  if (raw == null || raw.isEmpty) return wholeFile();

  final m = _bytesRange.firstMatch(raw);
  if (m == null) return wholeFile();

  final startRaw = m.group(1)!;
  final endRaw = m.group(2)!;

  // Suffix form `bytes=-N`: the last N bytes.
  if (startRaw.isEmpty) {
    if (endRaw.isEmpty || total == null) return const ResolvedRange(0, null);
    final n = int.tryParse(endRaw) ?? 0;
    final start = (total - n).clamp(0, total);
    return ResolvedRange(start, total - 1);
  }

  final parsedStart = int.tryParse(startRaw) ?? 0;
  final start = (total != null && parsedStart > total) ? total : parsedStart;

  if (endRaw.isEmpty) return ResolvedRange(start, null);
  final end = int.tryParse(endRaw) ?? start;
  return ResolvedRange(start, end);
}

/// Block indices covering the half-open byte range `[start, endExclusive)`.
///
/// Returns ascending, de-duplicated indices. An empty range yields no blocks.
List<int> blockIndicesFor({
  required int start,
  required int endExclusive,
  required int blockSize,
}) {
  if (blockSize <= 0 || endExclusive <= start) return const [];
  final first = start ~/ blockSize;
  final last = (endExclusive - 1) ~/ blockSize;
  return [for (var i = first; i <= last; i++) i];
}

/// Byte offset where [blockIndex] begins.
int blockStartOffset(int blockIndex, int blockSize) => blockIndex * blockSize;

/// Inclusive byte end for fetching [blockIndex], clamped to [total] when known.
int blockFetchEnd({
  required int blockIndex,
  required int blockSize,
  int? total,
}) {
  final end = blockStartOffset(blockIndex, blockSize) + blockSize - 1;
  if (total != null && end > total - 1) return total - 1;
  return end;
}
