import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/netdisk_range_proxy.dart';

/// Fake CDN that only serves explicit byte ranges and records every Range
/// header it receives, so we can prove the proxy never issues open-ended
/// requests.
void main() {
  const total = 9 * 1024 * 1024; // > 2 proxy chunks
  late Uint8List body;
  late HttpServer upstream;
  late int upstreamPort;
  final ranges = <String?>[];
  final userAgents = <String?>[];

  setUp(() async {
    body = Uint8List.fromList(List<int>.generate(total, (i) => i & 0xff));
    ranges.clear();
    userAgents.clear();
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstreamPort = upstream.port;
    upstream.listen((req) {
      final range = req.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      userAgents.add(req.headers.value(HttpHeaders.userAgentHeader));
      var start = 0;
      var end = total - 1;
      if (range != null) {
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        start = int.parse(m.group(1)!);
        final e = m.group(2);
        if (e != null && e.isNotEmpty) end = int.parse(e);
        if (end >= total) end = total - 1;
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set('Content-Range', 'bytes $start-$end/$total');
      } else {
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.set(HttpHeaders.contentLengthHeader, '$total');
      }
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.add(body.sublist(start, end + 1));
      unawaited(req.response.close());
    });
  });

  tearDown(() async {
    await NetdiskRangeProxy.instance.dispose();
    await upstream.close(force: true);
  });

  test('open-ended client request is served via bounded upstream ranges',
      () async {
    final local = await NetdiskRangeProxy.instance.register(
      upstreamUrl: 'http://127.0.0.1:$upstreamPort/movie.mp4',
      headers: {'User-Agent': 'medio-test'},
    );

    final client = HttpClient();
    final resp = await (await client.getUrl(Uri.parse(local))).close();
    expect(resp.statusCode, HttpStatus.partialContent);
    final bytes = await _collect(resp);
    client.close(force: true);

    expect(bytes.length, total);
    expect(bytes.sublist(0, 64), body.sublist(0, 64));
    expect(bytes.sublist(total - 64), body.sublist(total - 64));

    // Every upstream request must be a bounded range (explicit end).
    expect(ranges, isNotEmpty);
    for (final r in ranges) {
      expect(r, isNotNull);
      expect(RegExp(r'^bytes=\d+-\d+$').hasMatch(r!), isTrue,
          reason: 'upstream saw open-ended range: $r');
    }
    expect(ranges.first, 'bytes=0-${NetdiskRangeProxy.chunkSize - 1}');
    expect(ranges.length, greaterThan(1));
    expect(userAgents.every((u) => u == 'medio-test'), isTrue);
  });

  test('bounded client range is passed through and content is exact', () async {
    final local = await NetdiskRangeProxy.instance.register(
      upstreamUrl: 'http://127.0.0.1:$upstreamPort/movie.mp4',
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
    final local = await NetdiskRangeProxy.instance.register(
      upstreamUrl: 'http://127.0.0.1:$upstreamPort/movie.mp4',
    );
    NetdiskRangeProxy.instance.unregister(local);
    final client = HttpClient();
    final resp = await (await client.getUrl(Uri.parse(local))).close();
    expect(resp.statusCode, HttpStatus.notFound);
    await resp.drain<void>();
    client.close(force: true);
  });
}

Future<List<int>> _collect(HttpClientResponse resp) async {
  final out = <int>[];
  await for (final chunk in resp) {
    out.addAll(chunk);
  }
  return out;
}
