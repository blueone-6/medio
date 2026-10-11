/// Pure LRU eviction for the on-disk netdisk block cache.
///
/// Kept separate from the filesystem so the policy can be tested without IO.
library;

/// A cached block file's metadata.
class CacheEntry {
  const CacheEntry({
    required this.path,
    required this.sizeBytes,
    required this.lastUsed,
  });

  final String path;
  final int sizeBytes;
  final DateTime lastUsed;
}

/// Paths to delete so the total size of [entries] drops to `<= capBytes`.
///
/// Oldest [CacheEntry.lastUsed] first, and never more than necessary.
/// A non-positive [capBytes] evicts everything (cache disabled).
List<String> blocksToEvict(List<CacheEntry> entries, int capBytes) {
  if (capBytes <= 0) return [for (final e in entries) e.path];

  var total = 0;
  for (final e in entries) {
    total += e.sizeBytes;
  }
  if (total <= capBytes) return const [];

  final byAge = [...entries]..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
  final evicted = <String>[];
  for (final e in byAge) {
    if (total <= capBytes) break;
    evicted.add(e.path);
    total -= e.sizeBytes;
  }
  return evicted;
}
