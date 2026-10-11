import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/netdisk_cache_eviction.dart';

CacheEntry _entry(String name, int size, int ageMinutes) => CacheEntry(
      path: '/cache/$name',
      sizeBytes: size,
      lastUsed: DateTime(2026, 1, 1).add(Duration(minutes: ageMinutes)),
    );

void main() {
  group('blocksToEvict', () {
    test('nothing evicted when under cap', () {
      final entries = [_entry('a', 10, 1), _entry('b', 10, 2)];
      expect(blocksToEvict(entries, 100), isEmpty);
    });

    test('evicts oldest until within cap', () {
      final entries = [
        _entry('new', 10, 30),
        _entry('old', 10, 1),
        _entry('mid', 10, 15),
      ];
      expect(blocksToEvict(entries, 20), ['/cache/old']);
      expect(blocksToEvict(entries, 10), ['/cache/old', '/cache/mid']);
    });

    test('non-positive cap evicts everything (cache disabled)', () {
      final entries = [_entry('a', 10, 1), _entry('b', 10, 2)];
      expect(blocksToEvict(entries, 0), ['/cache/a', '/cache/b']);
      expect(blocksToEvict(entries, -5), ['/cache/a', '/cache/b']);
    });

    test('exact fit evicts nothing', () {
      final entries = [_entry('a', 10, 1), _entry('b', 10, 2)];
      expect(blocksToEvict(entries, 20), isEmpty);
    });

    test('evicts enough to fit a single oversized entry', () {
      final entries = [_entry('big', 1000, 1)];
      expect(blocksToEvict(entries, 10), ['/cache/big']);
    });
  });
}
