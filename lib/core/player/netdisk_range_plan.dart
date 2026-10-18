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

/// Number of bytes a cached/fetched block must hold.
///
/// Every block is exactly [blockSize] bytes except the final one, which is the
/// remainder of the file. Returns null when [total] is unknown, in which case a
/// short block cannot be told apart from the file's last block.
int? expectedBlockLength({
  required int blockIndex,
  required int blockSize,
  int? total,
}) {
  if (total == null) return null;
  final start = blockStartOffset(blockIndex, blockSize);
  if (start >= total) return 0;
  final remaining = total - start;
  return remaining < blockSize ? remaining : blockSize;
}

/// Parsed upstream `Content-Range: bytes <start>-<end>/<total>` response.
class ContentRangeHeader {
  const ContentRangeHeader({
    required this.start,
    required this.end,
    this.total,
  });

  final int start;
  final int end;

  /// Complete entity length, or null for `*`.
  final int? total;

  /// Declared payload length in bytes.
  int get length => end - start + 1;

  @override
  String toString() => 'ContentRange($start-$end/${total ?? '*'})';
}

final RegExp _contentRangePattern = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$');

/// Parses a `Content-Range` response header, or null when absent/malformed.
///
/// Only the single-range form is accepted, which is all a byte-range CDN
/// returns; anything else is treated as "no range information" so the caller
/// falls back to the requested length.
ContentRangeHeader? parseContentRangeHeader(String? value) {
  if (value == null) return null;
  final m = _contentRangePattern.firstMatch(value.trim());
  if (m == null) return null;
  final start = int.tryParse(m.group(1)!);
  final end = int.tryParse(m.group(2)!);
  if (start == null || end == null || end < start) return null;
  final totalRaw = m.group(3)!;
  final total = totalRaw == '*' ? null : int.tryParse(totalRaw);
  return ContentRangeHeader(start: start, end: end, total: total);
}

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
