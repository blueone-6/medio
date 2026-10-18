import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/netdisk_block_cache.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('netdisk_cache_test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Uint8List bytes(int n, int fill) =>
      Uint8List.fromList(List<int>.filled(n, fill));

  test('disabled cache never writes or reads', () async {
    final cache = NetdiskBlockCache(rootDir: root, limitBytes: 0);
    expect(cache.enabled, isFalse);
    await cache.write('item/1', 0, bytes(10, 7));
    expect(await cache.read('item/1', 0), isNull);
    expect(await cache.currentSizeBytes(), 0);
  });

  test('round-trips a block and serves it on second read', () async {
    final cache = NetdiskBlockCache(rootDir: root, limitBytes: 1024);
    await cache.write('item/1', 0, bytes(16, 42));
    final got = await cache.read('item/1', 0);
    expect(got, isNotNull);
    expect(got!.length, 16);
    expect(got.first, 42);
  });

  test('exists reports persisted blocks without reading them', () async {
    final cache = NetdiskBlockCache(rootDir: root, limitBytes: 1024);
    expect(await cache.exists('item/1', 0), isFalse);
    await cache.write('item/1', 0, bytes(16, 42));
    expect(await cache.exists('item/1', 0), isTrue);
    expect(await cache.exists('item/1', 1), isFalse);
    expect(await cache.exists('item/2', 0), isFalse);
  });

  test('separate cache keys and indices do not collide', () async {
    final cache = NetdiskBlockCache(rootDir: root, limitBytes: 4096);
    await cache.write('item/1', 0, bytes(4, 1));
    await cache.write('item/1', 1, bytes(4, 2));
    await cache.write('item/2', 0, bytes(4, 3));
    expect((await cache.read('item/1', 0))!.first, 1);
    expect((await cache.read('item/1', 1))!.first, 2);
    expect((await cache.read('item/2', 0))!.first, 3);
    expect(await cache.read('item/2', 1), isNull);
  });

  test('enforceLimit evicts oldest blocks to stay within the cap', () async {
    final cache = NetdiskBlockCache(rootDir: root, limitBytes: 30);
    await cache.write('item/1', 0, bytes(10, 1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cache.write('item/1', 1, bytes(10, 2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await cache.write('item/1', 2, bytes(10, 3));

    expect(await cache.currentSizeBytes(), 30);

    await cache.write('item/1', 3, bytes(10, 4));
    await cache.enforceLimit();

    expect(await cache.currentSizeBytes(), lessThanOrEqualTo(30));
    // The oldest block (index 0) should be the first to go.
    expect(await cache.read('item/1', 0), isNull);
    expect(await cache.read('item/1', 3), isNotNull);
  });

  test('sweep removes leftover temp files', () async {
    final dir = Directory('${root.path}${Platform.pathSeparator}item_1');
    await dir.create(recursive: true);
    final tmp = File('${dir.path}${Platform.pathSeparator}0.blk.tmp');
    await tmp.writeAsBytes(bytes(4, 9), flush: true);

    final cache = NetdiskBlockCache(rootDir: root, limitBytes: 1024);
    await cache.sweep();

    expect(await tmp.exists(), isFalse);
  });

  test('total metadata round-trips and is immutable', () async {
    final cache = NetdiskBlockCache(rootDir: root, limitBytes: 1024);
    expect(await cache.readTotal('item/1'), isNull);
    await cache.writeTotal('item/1', 123456);
    expect(await cache.readTotal('item/1'), 123456);
    await cache.writeTotal('item/1', 999); // ignored: total is immutable
    expect(await cache.readTotal('item/1'), 123456);
  });

  test('concurrent writes to the same block do not corrupt', () async {
    final cache = NetdiskBlockCache(rootDir: root, limitBytes: 1 << 20);
    await Future.wait([
      for (var i = 0; i < 8; i++) cache.write('item/1', 0, bytes(64, 5)),
    ]);
    final got = await cache.read('item/1', 0);
    expect(got, isNotNull);
    expect(got!.length, 64);
    expect(got.every((b) => b == 5), isTrue);
  });
}
