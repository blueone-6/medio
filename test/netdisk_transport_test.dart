import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/netdisk_block_cache.dart';
import 'package:media_client/core/player/netdisk_transport.dart';
import 'package:media_client/core/player/netdisk_types.dart';

/// Fake CDN that serves explicit byte ranges, records every Range header it
/// receives, and can be switched into 403 / 307 modes.
void main() {
  const total = 9 * 1024 * 1024; // > 2 transport chunks
  late Uint8List body;
  late HttpServer upstream;
  late int port;
  late String mode;
  late int requestCount;
  late int responseDelayMs;
  final ranges = <String?>[];
  final paths = <String>[];
  final truncatedBlocks = <int>{};

  setUp(() async {
    body = Uint8List.fromList(List<int>.generate(total, (i) => i & 0xff));
    ranges.clear();
    paths.clear();
    truncatedBlocks.clear();
    requestCount = 0;
    responseDelayMs = 0;
    mode = 'range';
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = upstream.port;
    upstream.listen((req) async {
      requestCount++;
      paths.add(req.uri.path);
      // A pinned, already-expired signed CDN URL.
      if ((mode == 'expired' || mode == 'dead') && req.uri.path == '/stale.mkv') {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      if (mode == 'dead' && req.uri.path == '/dead.mkv') {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      // The Emby stream URL: 307s to a freshly minted URL on every request.
      if (mode == 'expired' && req.uri.path == '/stream') {
        req.response.statusCode = HttpStatus.temporaryRedirect;
        req.response.headers.set(
            HttpHeaders.locationHeader, 'http://127.0.0.1:$port/fresh.mkv');
        await req.response.close();
        return;
      }
      if (mode == '307' && req.uri.path == '/stream') {
        req.response.statusCode = HttpStatus.temporaryRedirect;
        req.response.headers
            .set(HttpHeaders.locationHeader, 'http://127.0.0.1:$port/file.mp4');
        await req.response.close();
        return;
      }
      if (mode == '403once' && requestCount == 1) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      final range = req.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      // A CDN that ignores Range and always answers with the whole entity.
      if (mode == 'norange') {
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.set(HttpHeaders.contentLengthHeader, '$total');
        req.response.headers.contentType = ContentType('video', 'mp4');
        req.response.add(body);
        await req.response.close();
        return;
      }
      var start = 0;
      var end = total - 1;
      if (range != null) {
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        start = int.parse(m.group(1)!);
        final e = m.group(2);
        if (e != null && e.isNotEmpty) end = int.parse(e);
        if (end >= total) end = total - 1;
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
      } else {
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.set(HttpHeaders.contentLengthHeader, '$total');
      }
      req.response.headers.contentType = ContentType('video', 'mp4');
      if (responseDelayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: responseDelayMs));
      }
      // A body shorter than the Content-Range it just declared, on the first
      // request for one middle block only.
      var sendEnd = end;
      if (mode == 'short' &&
          start == NetdiskTransport.chunkSize &&
          truncatedBlocks.add(start)) {
        sendEnd = start + (end - start) ~/ 2;
      }
      req.response.add(body.sublist(start, sendEnd + 1));
      await req.response.close();
    });
  });

  tearDown(() async {
    await NetdiskTransport.instance.dispose();
    NetdiskTransport.instance.cache = null;
    await upstream.close(force: true);
  });

  test('open-ended request is served via bounded upstream ranges', () async {
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/movie.mp4',
      headers: {'User-Agent': 'medio-test'},
      cacheKey: 'item/1',
    );

    final bytes = await _get(local);
    expect(bytes.length, total);
    expect(bytes.sublist(0, 64), body.sublist(0, 64));
    expect(bytes.sublist(total - 64), body.sublist(total - 64));

    expect(ranges, isNotEmpty);
    for (final r in ranges) {
      expect(r, isNotNull);
      expect(RegExp(r'^bytes=\d+-\d+$').hasMatch(r!), isTrue,
          reason: 'upstream saw open-ended range: $r');
    }
    expect(ranges.first, 'bytes=0-${NetdiskTransport.chunkSize - 1}');
    expect(ranges.length, greaterThan(1));
  });

  test('bounded client range returns exact bytes and content-range', () async {
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/movie.mp4',
      cacheKey: 'item/2',
    );
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(local));
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=10-29');
    final resp = await req.close();
    expect(resp.statusCode, HttpStatus.partialContent);
    expect(resp.headers.value('content-range'), 'bytes 10-29/$total');
    final bytes = await _collect(resp);
    client.close(force: true);
    expect(bytes, body.sublist(10, 30));
  });

  test('unregistered routes return 404', () async {
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/movie.mp4',
      cacheKey: 'item/3',
    );
    NetdiskTransport.instance.unregister(local);
    final client = HttpClient();
    final resp = await (await client.getUrl(Uri.parse(local))).close();
    expect(resp.statusCode, HttpStatus.notFound);
    await resp.drain<void>();
    client.close(force: true);
  });

  test('serves blocks from the disk cache on a second play', () async {
    final cacheDir = await Directory.systemTemp.createTemp('netdisk_cache_2nd');
    addTearDown(() async {
      if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
    });
    NetdiskTransport.instance.cache =
        NetdiskBlockCache(rootDir: cacheDir, limitBytes: 64 * 1024 * 1024);

    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/movie.mp4',
      cacheKey: 'item/cached',
    );
    final first = await _get(local);
    expect(first.length, total);
    expect(ranges, isNotEmpty);

    ranges.clear();
    final second = await _get(local);
    expect(second.length, total);
    expect(second.sublist(0, 64), body.sublist(0, 64));
    // Everything came from disk: no new upstream range requests.
    expect(ranges, isEmpty);
  });

  test('transparently re-resolves on 403 and retries the segment', () async {
    mode = '403once';
    final upstreamUrl = 'http://127.0.0.1:$port/movie.mp4';
    var refreshes = 0;
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: upstreamUrl,
      cacheKey: 'item/resolve',
      refresh: () async {
        refreshes++;
        return ResolvedStreamTarget(url: upstreamUrl);
      },
    );
    final bytes = await _get(local);
    expect(bytes.length, total);
    expect(refreshes, 1);
  });

  test('follows a 307 redirect itself', () async {
    mode = '307';
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/stream',
      cacheKey: 'item/redirect',
    );
    final bytes = await _get(local);
    expect(bytes.length, total);
    expect(bytes.sublist(0, 64), body.sublist(0, 64));
  });

  test('an expired pinned URL recovers through the redirect upstream', () async {
    // The bug this guards: the transport pins one pre-resolved signed CDN URL,
    // which expires mid-session. Re-resolving can hand back the server's cached
    // (still dead) redirect, so recovery has to go through the redirecting
    // stream URL instead 鈥?that is what turned a 20 s seek stall into a normal
    // seek.
    mode = 'expired';
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/stale.mkv',
      cacheKey: 'item/expired',
      redirectUrl: 'http://127.0.0.1:$port/stream',
      refresh: () async =>
          throw StateError('refresh must not be needed when the URL expired'),
    );

    final bytes = await _get(local);

    expect(bytes.length, total);
    expect(bytes.sublist(0, 64), body.sublist(0, 64));
    expect(paths, contains('/fresh.mkv'));
  });

  test('a dead URL and a dead redirect give up instead of looping', () async {
    mode = 'dead';
    var refreshes = 0;
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/stale.mkv',
      cacheKey: 'item/dead',
      redirectUrl: 'http://127.0.0.1:$port/dead.mkv',
      refresh: () async {
        refreshes++;
        return ResolvedStreamTarget(url: 'http://127.0.0.1:$port/dead.mkv');
      },
    );

    final bytes = await _get(local);

    // No data reaches the client, and the recovery budget is spent once per
    // allowed refresh attempt: the request fails instead of retrying forever.
    expect(bytes.length, lessThan(total));
    expect(refreshes, lessThanOrEqualTo(NetdiskTransport.maxRefreshAttempts));
    expect(requestCount, lessThanOrEqualTo(8));
  });

  test('cache hit still answers ranged requests with 206 + content-range',
      () async {
    final cacheDir = await Directory.systemTemp.createTemp('netdisk_cache_seek');
    addTearDown(() async {
      if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
    });
    final cache =
        NetdiskBlockCache(rootDir: cacheDir, limitBytes: 64 * 1024 * 1024);
    NetdiskTransport.instance.cache = cache;
    // Seed block 0 and the total, as an earlier play would have.
    await cache.write(
      'item/seek',
      0,
      Uint8List.sublistView(body, 0, NetdiskTransport.chunkSize),
    );
    await cache.writeTotal('item/seek', total);

    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/movie.mp4',
      cacheKey: 'item/seek',
    );
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(local));
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=10-29');
    final resp = await req.close();
    expect(resp.statusCode, HttpStatus.partialContent);
    expect(resp.headers.value('content-range'), 'bytes 10-29/$total');
    final got = await _collect(resp);
    client.close(force: true);
    expect(got, body.sublist(10, 30));
    // Served entirely from cache: no upstream range requests.
    expect(ranges, isEmpty);
  });
  test('concurrent connections share one upstream fetch per block', () async {
    // Two player connections to the same file used to pull the same 4 MB block
    // twice (observed as a 2.2x duplicate-fetch ratio in the field), splitting
    // the per-connection CDN budget between identical bytes.
    responseDelayMs = 150;
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/movie.mp4',
      cacheKey: 'item/singleflight',
    );

    final results = await Future.wait([_get(local), _get(local)]);

    for (final bytes in results) {
      expect(bytes.length, total);
      expect(bytes.sublist(0, 64), body.sublist(0, 64));
    }
    final starts = upstreamStarts(ranges);
    expect(starts.length, greaterThan(1));
    expect(starts.toSet().length, starts.length,
        reason: 'duplicate upstream fetches: $ranges');
  });

  test('schedules the next blocks before the client asks for them', () async {
    // The relay used to fetch serially: while the player consumed block N, the
    // transport sat idle waiting on the next 4 MB fetch. The prefetcher kicks
    // off blocks N+1/N+2 right after block N is served.
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/movie.mp4',
      cacheKey: 'item/prefetch',
    );

    // Open-ended read (what the players send); consume exactly block 0, then
    // disconnect — the prefetcher must still pull the remaining blocks.
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(local));
    final resp = await req.close();
    var received = 0;
    await for (final chunk in resp) {
      received += chunk.length;
      if (received >= NetdiskTransport.chunkSize) break;
    }
    client.close(force: true);

    final lastBlockStart = (total - 1) ~/ NetdiskTransport.chunkSize *
        NetdiskTransport.chunkSize;
    await _waitFor(
      () => upstreamStarts(ranges).contains(lastBlockStart),
      what: 'prefetch of the final block', ranges: ranges,
    );
    final starts = upstreamStarts(ranges);
    expect(starts, contains(NetdiskTransport.chunkSize),
        reason: 'block 1 was never prefetched: $starts');
    for (final s in starts) {
      expect(s, lessThan(total), reason: 'prefetched past EOF: $starts');
    }
  });

  test('prefetch does not run past a bounded client range', () async {
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/movie.mp4',
      cacheKey: 'item/prefetch-end',
    );

    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(local));
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-99');
    final resp = await req.close();
    await _collect(resp);
    client.close(force: true);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(upstreamStarts(ranges), everyElement(0),
        reason: 'prefetched beyond the requested range: $ranges');
  });

  test('a truncated upstream block is retried instead of ending the relay',
      () async {
    // A 206 body shorter than the Content-Range it declared used to be served
    // as-is and end the relay (`data.length < chunkSize` broke the loop), so
    // the player saw EOF in the middle of the file. It was also cached, which
    // replayed the same hole on the next play.
    mode = 'short';
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/movie.mp4',
      cacheKey: 'item/short-block',
    );

    final bytes = await _get(local);

    expect(bytes.length, total);
    expect(bytes.sublist(0, 64), body.sublist(0, 64));
    expect(bytes.sublist(total - 64), body.sublist(total - 64));
    final blockOne = ranges
        .where((r) =>
            r?.startsWith('bytes=${NetdiskTransport.chunkSize}-') ?? false)
        .length;
    expect(blockOne, greaterThan(1),
        reason: 'the truncated block was not re-fetched: $ranges');
  });

  test('a short block in the disk cache is discarded and re-fetched', () async {
    final cacheDir = await Directory.systemTemp.createTemp('netdisk_short_blk');
    addTearDown(() async {
      if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
    });
    final cache =
        NetdiskBlockCache(rootDir: cacheDir, limitBytes: 64 * 1024 * 1024);
    NetdiskTransport.instance.cache = cache;
    // A block written by a run that accepted a truncated 206.
    await cache.write(
      'item/short-cache',
      0,
      Uint8List.sublistView(body, 0, NetdiskTransport.chunkSize ~/ 2),
    );
    await cache.writeTotal('item/short-cache', total);

    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/movie.mp4',
      cacheKey: 'item/short-cache',
    );

    final bytes = await _get(local);

    expect(bytes.length, total);
    expect(bytes.sublist(0, 64), body.sublist(0, 64));
    expect(upstreamStarts(ranges), contains(0),
        reason: 'the truncated cached block was not re-fetched');
  });

  test('a 200 that ignores Range is sliced to the requested offset', () async {
    // Some netdisks answer `Range: bytes=N-` with a bare 200 and the whole
    // file. Forwarding it from byte 0 made the player skip N bytes itself and
    // kept a full-file relay open; the transport now answers 206 from N.
    mode = 'norange';
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/movie.mp4',
      cacheKey: 'item/whole-file',
    );

    final offset = 5 * 1000 * 1000;
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(local));
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-${offset + 99}');
    final resp = await req.close();
    expect(resp.statusCode, HttpStatus.partialContent);
    expect(
      resp.headers.value(HttpHeaders.contentRangeHeader),
      'bytes $offset-${offset + 99}/$total',
    );
    final got = await _collect(resp);
    client.close(force: true);
    expect(got, body.sublist(offset, offset + 100));
  });

  test('a 200 that ignores Range serves an open-ended offset as 206', () async {
    mode = 'norange';
    final local = await NetdiskTransport.instance.register(
      upstreamUrl: 'http://127.0.0.1:$port/movie.mp4',
      cacheKey: 'item/whole-file-open',
    );

    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(local));
    req.headers
        .set(HttpHeaders.rangeHeader, 'bytes=${NetdiskTransport.chunkSize}-');
    final resp = await req.close();
    expect(resp.statusCode, HttpStatus.partialContent);
    final got = await _collect(resp);
    client.close(force: true);
    expect(
      got,
      body.sublist(NetdiskTransport.chunkSize),
    );
    expect(
      resp.headers.value(HttpHeaders.contentRangeHeader),
      'bytes ${NetdiskTransport.chunkSize}-${total - 1}/$total',
    );
  });
}

/// Upstream range starts observed so far, in request order.
List<int> upstreamStarts(List<String?> ranges) => [
      for (final r in ranges)
        if (r != null) int.parse(RegExp(r'bytes=(\d+)-').firstMatch(r)!.group(1)!),
    ];

Future<void> _waitFor(bool Function() condition,
    {required String what,
    List<String?> ranges = const [],
    Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for $what; ranges=$ranges');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<List<int>> _get(String url) async {
  final client = HttpClient();
  final resp = await (await client.getUrl(Uri.parse(url))).close();
  final bytes = await _collect(resp);
  client.close(force: true);
  return bytes;
}

Future<List<int>> _collect(HttpClientResponse resp) async {
  final out = <int>[];
  await for (final chunk in resp) {
    out.addAll(chunk);
  }
  return out;
}
