import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/netdisk_stale_reader.dart';
import 'package:media_client/core/player/netdisk_transport.dart';

/// The transport serves one file over several localhost connections. Field
/// capture (docs/specs/2026-10-18-netdisk-buffering-todo.md) showed Media3
/// closing its Matroska probe loads 26–79 ms after opening them while the
/// socket stayed open and kept draining the transport's open-ended response —
/// those relays kept pulling from the CDN for minutes and split the
/// per-connection budget with the real playback stream.
void main() {
  group('isStaleReader', () {
    const minAlive = Duration(seconds: 6);
    const minDistance = 64 * 1024 * 1024;

    bool stale({
      required int id,
      required int position,
      required int newestId,
      required int newestPosition,
      Duration alive = const Duration(seconds: 30),
      Duration newestAlive = const Duration(seconds: 30),
    }) =>
        isStaleReader(
          id: id,
          positionBytes: position,
          alive: alive,
          newestId: newestId,
          newestPositionBytes: newestPosition,
          newestAlive: newestAlive,
          minDistanceBytes: minDistance,
          minAlive: minAlive,
        );

    test('the newest reader is never stale', () {
      expect(
        stale(
            id: 4, position: 0, newestId: 4, newestPosition: 90 * 1024 * 1024),
        isFalse,
      );
    });

    test('an older reader far from the newest one is stale', () {
      // The observed case: playback at 14.2 GB, probe relay still at 0.
      expect(
        stale(
          id: 1,
          position: 0,
          newestId: 4,
          newestPosition: 15 * 1000 * 1000 * 1000,
        ),
        isTrue,
      );
    });

    test('a reader near the newest one is not stale', () {
      expect(
        stale(
          id: 3,
          position: 100 * 1024 * 1024,
          newestId: 4,
          newestPosition: 100 * 1024 * 1024 + 1024,
        ),
        isFalse,
      );
    });

    test('a young probe is spared even when it is far away', () {
      // Matroska tail read: opens at EOF, finishes in under a second.
      expect(
        stale(
          id: 2,
          position: 29 * 1000 * 1000 * 1000,
          newestId: 4,
          newestPosition: 15 * 1000 * 1000 * 1000,
          alive: const Duration(milliseconds: 90),
          newestAlive: const Duration(milliseconds: 200),
        ),
        isFalse,
      );
      expect(
        stale(
          id: 2,
          position: 29 * 1000 * 1000 * 1000,
          newestId: 4,
          newestPosition: 15 * 1000 * 1000 * 1000,
          alive: const Duration(seconds: 30),
          newestAlive: const Duration(milliseconds: 200),
        ),
        isFalse,
      );
    });

    test('a reader judged stale stays stale across a new anchor', () {
      // A seek opens a new reader; the abandoned ones must not get a fresh
      // full-speed window because the anchor is young again.
      expect(
        isStaleReader(
          id: 1,
          positionBytes: 0,
          alive: const Duration(seconds: 30),
          newestId: 5,
          newestPositionBytes: 14 * 1000 * 1000 * 1000,
          newestAlive: const Duration(milliseconds: 100),
          minDistanceBytes: minDistance,
          minAlive: minAlive,
          wasStale: true,
        ),
        isTrue,
      );
      // ...but a reader that comes back near the anchor is active again.
      expect(
        isStaleReader(
          id: 1,
          positionBytes: 14 * 1000 * 1000 * 1000 + 1024,
          alive: const Duration(seconds: 30),
          newestId: 5,
          newestPositionBytes: 14 * 1000 * 1000 * 1000,
          newestAlive: const Duration(milliseconds: 100),
          minDistanceBytes: minDistance,
          minAlive: minAlive,
          wasStale: true,
        ),
        isFalse,
      );
    });
  });

  group('transport stale sweep', () {
    // Large enough that neither reader reaches EOF during the test: the bug is
    // about long-lived open-ended readers, and a relay that finishes naturally
    // would never be judged.
    const total = 8 * 1024 * 1024 * 1024;
    const blockSize = 4 * 1024 * 1024;
    late Uint8List body;
    late HttpServer upstream;
    late int port;
    late HttpClient client;
    late List<String> logs;
    late DebugPrintCallback originalPrint;

    setUp(() async {
      body = Uint8List.fromList(List<int>.generate(blockSize, (i) => i & 0xff));
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = upstream.port;
      upstream.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range ?? '');
        final start = m == null ? 0 : int.parse(m.group(1)!);
        final rawEnd = m?.group(2);
        var end = (rawEnd == null || rawEnd.isEmpty)
            ? start + blockSize - 1
            : int.parse(rawEnd);
        if (end >= total) end = total - 1;
        if (end - start + 1 > blockSize) end = start + blockSize - 1;
        // A throttled CDN connection: each block takes long enough that the
        // readers overlap for seconds, as in the field.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
        req.response.headers.contentType = ContentType('video', 'x-matroska');
        req.response.add(body.sublist(0, end - start + 1));
        await req.response.close();
      });

      client = HttpClient();
      logs = <String>[];
      originalPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      NetdiskTransport.staleGrace = const Duration(milliseconds: 200);
      NetdiskTransport.staleBlockDelay = const Duration(milliseconds: 50);
      NetdiskTransport.staleDropAfter = const Duration(milliseconds: 400);
      NetdiskTransport.staleSweepInterval = const Duration(milliseconds: 50);
      NetdiskTransport.staleDistanceBytes = 1024 * 1024;
    });

    tearDown(() async {
      debugPrint = originalPrint;
      client.close(force: true);
      await NetdiskTransport.instance.dispose();
      NetdiskTransport.instance.cache = null;
      NetdiskTransport.staleGrace = const Duration(seconds: 6);
      NetdiskTransport.staleBlockDelay = const Duration(seconds: 8);
      NetdiskTransport.staleDropAfter = const Duration(seconds: 30);
      NetdiskTransport.staleSweepInterval = const Duration(seconds: 2);
      NetdiskTransport.staleDistanceBytes = 64 * 1024 * 1024;
      await upstream.close(force: true);
    });

    test('a reader left behind by a newer one is throttled and then dropped',
        () async {
      final local = await NetdiskTransport.instance.register(
        upstreamUrl: 'http://127.0.0.1:$port/movie.mkv',
        cacheKey: 'item/stale',
      );

      // The probe-like reader Media3 opens first, from byte 0.
      final probe = await _open(client, local, 'bytes=0-');
      final probeSub = probe.listen((_) {});

      // A little later, the load the player is actually positioned on.
      final playback =
          await _open(client, local, 'bytes=${4 * 1024 * 1024 * 1024}-');
      final playbackSub = playback.listen((_) {});

      await Future<void>.delayed(const Duration(milliseconds: 2500));

      final transportLogs =
          logs.where((l) => l.contains('MEDIO-TRANSPORT')).toList();
      expect(
        transportLogs.any((l) => l.contains('relay #1 stale')),
        isTrue,
        reason: 'logs: $transportLogs',
      );
      expect(
        transportLogs.any((l) => l.contains('relay #1 dropped')),
        isTrue,
        reason: 'a stale relay must stop pulling from the CDN: $transportLogs',
      );
      expect(
        transportLogs.any((l) => l.contains('relay #1 done')),
        isTrue,
        reason: 'dropping the relay must close its response: $transportLogs',
      );
      // The playback reader is untouched.
      expect(transportLogs.any((l) => l.contains('relay #2 stale')), isFalse);
      expect(transportLogs.any((l) => l.contains('relay #2 done')), isFalse);

      await probeSub.cancel();
      await playbackSub.cancel();
    });
  });
}

Future<HttpClientResponse> _open(
  HttpClient client,
  String url,
  String range,
) async {
  final req = await client.getUrl(Uri.parse(url));
  req.headers.set(HttpHeaders.rangeHeader, range);
  return req.close();
}
