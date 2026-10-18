import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../logging/app_log.dart';
import 'netdisk_cache_eviction.dart';

/// On-disk, block-aligned byte cache for the netdisk transport.
///
/// Blocks live at `<root>/<cacheKey>/<blockIndex>.blk`. LRU order is derived
/// from file mtimes (no index file, no new dependencies). A non-positive
/// [limitBytes] disables the cache entirely.
class NetdiskBlockCache {
  NetdiskBlockCache({required this.rootDir, required this.limitBytes});

  final Directory rootDir;
  final int limitBytes;

  bool get enabled => limitBytes > 0;

  static const String _ext = '.blk';
  static const String _tmpExt = '.tmp';

  String _dirPath(String cacheKey) {
    final segments = cacheKey
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(_sanitize)
        .toList(growable: false);
    final safe = segments.isEmpty ? '_' : segments.join(Platform.pathSeparator);
    return '${rootDir.path}${Platform.pathSeparator}$safe';
  }

  File _blockFile(String cacheKey, int blockIndex) =>
      File('${_dirPath(cacheKey)}${Platform.pathSeparator}$blockIndex$_ext');

  File _totalFile(String cacheKey) =>
      File('${_dirPath(cacheKey)}${Platform.pathSeparator}total.txt');

  /// Whether [blockIndex] is already persisted for [cacheKey].
  ///
  /// A stat-only probe: the transport's block prefetcher uses it to skip a
  /// fetch without paying for a full block read.
  Future<bool> exists(String cacheKey, int blockIndex) async {
    if (!enabled) return false;
    try {
      return await _blockFile(cacheKey, blockIndex).exists();
    } catch (_) {
      return false;
    }
  }

  /// Reads the cached total size for [cacheKey], or null when unknown.
  ///
  /// The transport needs the total up front to answer ranged requests with a
  /// proper `Content-Range` (a 200 answer makes the player stream
  /// non-seekable).
  Future<int?> readTotal(String cacheKey) async {
    if (!enabled) return null;
    try {
      final file = _totalFile(cacheKey);
      if (!await file.exists()) return null;
      final n = int.tryParse((await file.readAsString()).trim());
      return (n != null && n > 0) ? n : null;
    } catch (_) {
      return null;
    }
  }

  /// Persists the total size for [cacheKey] (immutable once known).
  Future<void> writeTotal(String cacheKey, int total) async {
    if (!enabled || total <= 0) return;
    try {
      final file = _totalFile(cacheKey);
      if (await file.exists()) return;
      await file.parent.create(recursive: true);
      await file.writeAsString('$total', flush: true);
    } catch (_) {}
  }

  /// Reads a whole block, or null on miss / failure.
  Future<Uint8List?> read(String cacheKey, int blockIndex) async {
    if (!enabled) return null;
    final file = _blockFile(cacheKey, blockIndex);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      unawaited(file.setLastModified(DateTime.now()).catchError((_) => file));
      return bytes;
    } catch (e) {
      AppLog.instance.d('NetdiskCache', 'read miss $cacheKey/$blockIndex: $e');
      return null;
    }
  }

  int _tmpSeq = 0;

  /// Writes a whole block atomically (temp file + rename). Failures are
  /// non-fatal: playback still gets the bytes from the network path.
  Future<void> write(String cacheKey, int blockIndex, Uint8List bytes) async {
    if (!enabled || bytes.isEmpty) return;
    final target = _blockFile(cacheKey, blockIndex);
    // Unique temp name: the player can open several parallel connections that
    // fetch the same block, and a shared temp path collides on Windows
    // (errno 32, "another process is using this file").
    final tmp = File('${target.path}.${_tmpSeq++}$_tmpExt');
    try {
      await target.parent.create(recursive: true);
      await tmp.writeAsBytes(bytes, flush: true);
      try {
        await tmp.rename(target.path);
      } on FileSystemException {
        // Rename over a file that is open for reading fails on Windows; drop
        // the old copy and retry once.
        try {
          await target.delete();
        } catch (_) {}
        await tmp.rename(target.path);
      }
    } catch (e) {
      AppLog.instance.d('NetdiskCache', 'write failed $cacheKey/$blockIndex: $e');
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  /// Deletes blocks (oldest first) until the cache is within [limitBytes],
  /// then prunes empty key directories. Call on startup and after writes.
  Future<void> enforceLimit() async {
    if (!enabled) return;
    try {
      if (!await rootDir.exists()) return;
      final entries = <CacheEntry>[];
      await for (final entity in rootDir.list(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith(_ext)) continue;
        final stat = await entity.stat();
        entries.add(CacheEntry(
          path: entity.path,
          sizeBytes: stat.size,
          lastUsed: stat.modified,
        ));
      }
      final doomed = blocksToEvict(entries, limitBytes);
      if (doomed.isEmpty) return;
      for (final path in doomed) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      AppLog.instance.i(
        'NetdiskCache',
        'evicted ${doomed.length} block(s) of ${entries.length}',
      );
      await _pruneEmptyDirs();
    } catch (e) {
      AppLog.instance.d('NetdiskCache', 'enforceLimit failed: $e');
    }
  }

  /// Startup sweep: prune temp leftovers and enforce the size cap.
  Future<void> sweep() async {
    try {
      if (await rootDir.exists()) {
        await for (final entity in rootDir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith(_tmpExt)) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    await enforceLimit();
  }

  /// Current total size in bytes (test/diagnostics helper).
  Future<int> currentSizeBytes() async {
    if (!await rootDir.exists()) return 0;
    var total = 0;
    await for (final entity in rootDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith(_ext)) {
        total += (await entity.stat()).size;
      }
    }
    return total;
  }

  Future<void> _pruneEmptyDirs() async {
    try {
      await for (final entity in rootDir.list()) {
        if (entity is Directory) {
          final children = await entity.list().toList();
          if (children.isEmpty) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  static String _sanitize(String segment) =>
      segment.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
