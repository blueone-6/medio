import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/netdisk_range_plan.dart';

void main() {
  group('resolveRangeRequest', () {
    test('null header means whole file', () {
      final r = resolveRangeRequest(null, 1000);
      expect(r.start, 0);
      expect(r.end, 999);
      expect(r.length(1000), 1000);
    });

    test('unknown total yields open-ended whole file', () {
      final r = resolveRangeRequest(null, null);
      expect(r.start, 0);
      expect(r.end, isNull);
      expect(r.length(null), isNull);
    });

    test('open-ended from a start offset', () {
      final r = resolveRangeRequest('bytes=100-', 1000);
      expect(r.start, 100);
      expect(r.end, isNull);
      expect(r.length(1000), 900);
    });

    test('closed range is inclusive', () {
      final r = resolveRangeRequest('bytes=100-200', 1000);
      expect(r.start, 100);
      expect(r.end, 200);
      expect(r.length(1000), 101);
    });

    test('suffix range needs total', () {
      expect(resolveRangeRequest('bytes=-100', 1000).start, 900);
      expect(resolveRangeRequest('bytes=-100', 1000).end, 999);
      expect(resolveRangeRequest('bytes=-100', null).end, isNull);
    });

    test('start beyond total is clamped', () {
      expect(resolveRangeRequest('bytes=5000-', 1000).start, 1000);
    });

    test('unparseable falls back to whole file', () {
      expect(resolveRangeRequest('garbage', 500).start, 0);
      expect(resolveRangeRequest('garbage', 500).end, 499);
    });
  });

  group('blockIndicesFor', () {
    test('covers partial first block to partial last block', () {
      expect(blockIndicesFor(start: 0, endExclusive: 10, blockSize: 4), [0, 1, 2]);
    });

    test('aligned end excludes the next block', () {
      expect(blockIndicesFor(start: 0, endExclusive: 8, blockSize: 4), [0, 1]);
    });

    test('mid-file window spans only touched blocks', () {
      expect(blockIndicesFor(start: 5, endExclusive: 13, blockSize: 4), [1, 2, 3]);
    });

    test('empty range yields no blocks', () {
      expect(blockIndicesFor(start: 5, endExclusive: 5, blockSize: 4), isEmpty);
      expect(blockIndicesFor(start: 5, endExclusive: 4, blockSize: 4), isEmpty);
    });
  });

  group('blockFetchEnd', () {
    test('full block when total unknown', () {
      expect(blockFetchEnd(blockIndex: 1, blockSize: 4, total: null), 7);
    });

    test('last block clamps to total', () {
      expect(blockFetchEnd(blockIndex: 2, blockSize: 4, total: 10), 9);
    });
  });
}
