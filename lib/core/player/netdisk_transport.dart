import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../logging/app_log.dart';
import 'netdisk_block_cache.dart';
import 'netdisk_range_plan.dart';
import 'netdisk_recovery.dart';
import 'netdisk_types.dart';

/// Localhost HTTP transport for **all** netdisk / strm playback.
///
/// The player opens a stable `http://127.0.0.1:<port>/<id>` URL; the transport
/// fetches block-aligned byte ranges from the real upstream so it can:
///   * turn open-ended requests into bounded ranges (Quark throttling);
///   * inject per-CDN headers (115 hotlink Referer, Quark UA-only);
///   * follow 307/302 redirects itself (no player-side emby_307 branch);
///   * transparently re-resolve an expired signed URL and retry the segment;
///   * serve/reuse bytes from an on-disk block cache.
///
/// The real upstream URL (with its signed token) never reaches the player.
class NetdiskTransport {
  NetdiskTransport._();

  static final NetdiskTransport instance = NetdiskTransport._();

  /// Monotonic id for relay diagnostics (see `_stream`).
  static int _relaySeq = 0;

  /// Upstream chunk / cache block size.
  static const int chunkSize = 4 * 1024 * 1024;

  /// Blocks fetched ahead of the serving position, per connection.
  ///
  /// The netdisk CDNs throttle per connection (~10 Mbps observed), so the
  /// serial "fetch 4 MB, then serve" loop tops out at one connection's budget
  /// no matter how much link headroom exists. Fetching the next blocks while
  /// the player consumes the current one hides that round-trip and lets the
  /// per-file concurrency cap raise the effective throughput.
  static const int prefetchDepth = 2;

  /// Cap on concurrent upstream fetches for one file (serving fetch + the
  /// prefetch window). Multiple player connections to the same file share
  /// this budget through the single-flight map below.
  ///
  /// Sized for ~4 concurrent player connections (video/audio/text tracks of
  /// one remux each pull serially): each gets its serving fetch plus part of
  /// the prefetch window. The netdisk CDN throttles per connection, so this
  /// cap is what sets the aggregate ceiling (~20 Mbps per connection).
  static const int maxInflightPerFile = 8;

  /// Recently completed fetches kept when the disk cache is off, so a block
  /// prefetched by an eager connection is not re-fetched by a connection that
  /// reaches it after its future was dropped. Shared by every reader (block
  /// content is immutable); evicted LRU once [_recentCap] is exceeded.
  ///
  /// Sized to hold the whole prefetch window ([prefetchDepth] per active
  /// connection): evicting an unconsumed prefetched block would re-fetch it.
  static const int _recentCap = 8;

  static const Duration _connectTimeout = Duration(seconds: 15);
  static const int maxRefreshAttempts = 2;

  HttpServer? _server;
  int _nextRouteId = 1;
  final Map<String, _Route> _routes = {};

  /// In-flight upstream fetches, keyed per file block. Concurrent player
  /// connections (and the prefetcher) join the same future instead of
  /// downloading identical bytes twice — that duplicate fetching measured
  /// ~2.2x in the field and burned most of the CDN budget.
  final Map<String, Future<_BlockOutcome>> _inflight = {};
  final Map<String, int> _inflightByKey = {};
  final Map<String, _BlockOutcome> _recent = {};

  /// Disk block cache; null (or a disabled cache) means no persistence.
  NetdiskBlockCache? cache;

  bool get _cacheUsable => cache?.enabled ?? false;

  static String _blockKey(String cacheKey, int blockIndex) =>
      '$cacheKey|$blockIndex';

  /// Registers [upstreamUrl] and returns the localhost URL to hand the player.
  ///
  /// [redirectUrl] is the stable server stream URL that 307s to a *fresh* signed
  /// URL per request. It is kept as a fallback for the case where the
  /// pre-resolved [upstreamUrl] expires: re-resolving can return the same dead
  /// URL (the server caches its redirect for minutes), whereas retrying through
  /// the redirecting URL mints a new one immediately.
  Future<String> register({
    required String upstreamUrl,
    Map<String, String>? headers,
    required String cacheKey,
    String? redirectUrl,
    Future<ResolvedStreamTarget> Function()? refresh,
  }) async {
    final server = await _ensureServer();
    final id = '${_nextRouteId++}';
    _routes[id] = _Route(
      upstreamUrl: upstreamUrl,
      headers: headers ?? const {},
      cacheKey: cacheKey,
      redirectUrl: redirectUrl,
      refresh: refresh,
    );
    final local = 'http://127.0.0.1:${server.port}/$id';
    AppLog.instance.i('NetdiskTransport', 'route $id registered (proxy=$local)');
    return local;
  }

  /// Drops the route behind [localUrl], if any.
  ///
  /// Also aborts the route's in-flight upstream fetches: the player is
  /// replacing this route (stall recovery / re-open), and a zombie relay that
  /// keeps downloading duplicates the new route's blocks.
  void unregister(String localUrl) {
    final segments = Uri.tryParse(localUrl)?.pathSegments;
    if (segments == null || segments.isEmpty) return;
    final route = _routes.remove(segments.first);
    if (route != null) {
      route.disposeClient();
      AppLog.instance
          .d('NetdiskTransport', 'route ${segments.first} unregistered');
    }
  }

  /// Closes the localhost server and clears all routes (shutdown / tests).
  Future<void> dispose() async {
    for (final route in _routes.values) {
      route.disposeClient();
    }
    _routes.clear();
    _inflight.clear();
    _inflightByKey.clear();
    _recent.clear();
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
  }

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    _server = server;
    server.listen(
      (req) => unawaited(_onRequest(req)),
      onError: (Object e) =>
          AppLog.instance.w('NetdiskTransport', 'server error: $e'),
    );
    AppLog.instance
        .i('NetdiskTransport', 'listening on 127.0.0.1:${server.port}');
    return server;
  }

  Future<void> _onRequest(HttpRequest req) async {
    final segments = req.uri.pathSegments;
    final route = segments.isEmpty ? null : _routes[segments.first];
    if (route == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    if (req.method != 'GET' && req.method != 'HEAD') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      await req.response.close();
      return;
    }
    await _stream(req, route);
  }
  Future<void> _stream(HttpRequest req, _Route route) async {
    final resp = req.response;
    final isHead = req.method == 'HEAD';
    final clientReq = resolveRangeRequest(
      req.headers.value(HttpHeaders.rangeHeader),
      null,
    );
    final requestedEnd = clientReq.end;
    var pos = clientReq.start;

    // Relay diagnostics: high-bitrate remuxes (40 Mbps+) stall when the phone
    // cannot sustain the bitrate, and the player only reports "rebuffering".
    // Logging the achieved throughput and slow upstream block fetches makes the
    // real bottleneck visible in the app log / diagnostics screen.
    final relayStartedAt = DateTime.now();
    var relayBytes = 0;
    var blocksServed = 0;
    var cacheHits = 0;
    var lastThroughputLogBytes = 0;
    final relayId = ++_relaySeq;
    final clientPort = req.connectionInfo?.remotePort ?? 0;
    AppLog.instance.i(
      'NetdiskTransport',
      'relay #$relayId start range=${req.headers.value(HttpHeaders.rangeHeader) ?? '-'} '
          'client=$clientPort upstream=${AppLog.redactUrl(route.upstreamUrl)}',
    );
    // logcat-visible (the AppLog file is not reachable on a release install) so a
    // slow seek can be attributed to the transport or to the player.
    debugPrint(
      'MEDIO-TRANSPORT relay #$relayId route=${route.cacheKey} range='
      '${req.headers.value(HttpHeaders.rangeHeader) ?? '-'}',
    );
    const throughputLogEveryBytes = 32 * 1024 * 1024;
    const slowBlockFetchThresholdMs = 1500;

    int? total;
    ContentType? contentType;
    var headersWritten = false;

    try {
      while (true) {
        if (total != null && pos >= total) break;
        if (requestedEnd != null && pos > requestedEnd) break;

        final blockIndex = pos ~/ chunkSize;
        final blockStart = blockStartOffset(blockIndex, chunkSize);
        final key = _blockKey(route.cacheKey, blockIndex);

        // A completed prefetch (no disk cache) is served straight from the
        // shared single-flight slot instead of being re-fetched.
        final prefetched = _takeRecent(key);
        var block = prefetched?.bytes;
        final fromCache = block != null;

        block ??= await cache?.read(route.cacheKey, blockIndex);

        // A cache hit has no upstream response to read `total` from, so recover
        // it from the cached metadata. Without a known total the response would
        // be a bare 200 (no Content-Range) and mpv would treat the localhost
        // stream as non-seekable ("Cannot seek in this stream.").
        if (block != null && total == null) {
          total = await cache?.readTotal(route.cacheKey);
        }

        if (block == null || total == null) {
          final fetchStartedAt = DateTime.now();
          final outcome = await _fetchShared(route, blockIndex, total);
          final fetchMs =
              DateTime.now().difference(fetchStartedAt).inMilliseconds;
          final relay = outcome.wholeFile;
          if (relay != null) {
            route.wholeFileMode = true;
            return await _relayWholeFile(resp, relay, headersWritten, isHead);
          }
          if (outcome.bytes == null) {
            if (block == null) break;
          } else {
            if (fetchMs >= slowBlockFetchThresholdMs) {
              final mbps = outcome.bytes!.length * 8 / (fetchMs * 1000.0);
              AppLog.instance.w(
                'NetdiskTransport',
                'slow upstream block #$blockIndex: '
                    '${(outcome.bytes!.length / 1048576).toStringAsFixed(1)}MB in '
                    '${fetchMs}ms (${mbps.toStringAsFixed(1)} Mbps)',
              );
            }
            total = outcome.total ?? total;
            contentType ??= outcome.contentType;
            block ??= outcome.bytes;
          }
        }
        final data = block;
        if (data == null || data.isEmpty) break;

        if (!headersWritten) {
          _writeResponseHeaders(resp, clientReq, total, contentType);
          headersWritten = true;
          if (isHead) {
            await resp.close();
            return;
          }
          await resp.flush();
        }
        final serveFrom = pos - blockStart;
        if (serveFrom < 0 || serveFrom >= data.length) break;
        var serveTo = data.length;
        if (requestedEnd != null && blockStart + serveTo > requestedEnd + 1) {
          serveTo = requestedEnd + 1 - blockStart;
        }
        final slice = (serveFrom == 0 && serveTo == data.length)
            ? data
            : Uint8List.sublistView(data, serveFrom, serveTo);
        resp.add(slice);
        await resp.flush();
        pos = blockStart + serveTo;
        relayBytes += slice.length;
        blocksServed++;
        if (fromCache) cacheHits++;

        // Fetch the next blocks while the player consumes this one, so the
        // serial 4 MB round-trip never sits on the critical path.
        _schedulePrefetch(route, blockIndex, total, requestedEnd);

        if (relayBytes - lastThroughputLogBytes >= throughputLogEveryBytes) {
          lastThroughputLogBytes = relayBytes;
          final seconds =
              DateTime.now().difference(relayStartedAt).inMilliseconds / 1000.0;
          final mbps = seconds > 0 ? relayBytes * 8 / (seconds * 1000000.0) : 0.0;
          AppLog.instance.i(
            'NetdiskTransport',
            'relay ${(relayBytes / 1048576).toStringAsFixed(0)}MB in '
                '${seconds.toStringAsFixed(0)}s = ${mbps.toStringAsFixed(1)} Mbps '
                '(blocks=$blocksServed cacheHits=$cacheHits)',
          );
        }

        if (total != null && pos >= total) break;
        if (data.length < chunkSize) break;
      }
    } catch (e) {
      AppLog.instance.d('NetdiskTransport', 'stream ended: $e');
    } finally {
      final seconds =
          DateTime.now().difference(relayStartedAt).inMilliseconds / 1000.0;
      if (seconds >= 5 && !isHead) {
        final mbps = relayBytes * 8 / (seconds * 1000000.0);
        AppLog.instance.i(
          'NetdiskTransport',
          'relay #$relayId closed: ${(relayBytes / 1048576).toStringAsFixed(1)}MB in '
              '${seconds.toStringAsFixed(1)}s = ${mbps.toStringAsFixed(1)} Mbps '
              '(blocks=$blocksServed cacheHits=$cacheHits client=$clientPort)',
        );
      }
      try {
        await resp.close();
      } catch (_) {}
    }
  }

  void _writeResponseHeaders(
    HttpResponse resp,
    ResolvedRange clientReq,
    int? total,
    ContentType? contentType,
  ) {
    if (total == null || total <= 0) {
      resp.statusCode = HttpStatus.ok;
      if (contentType != null) resp.headers.contentType = contentType;
      return;
    }
    final start = clientReq.start.clamp(0, total - 1);
    final last = (clientReq.end ?? (total - 1)).clamp(start, total - 1);
    resp.statusCode = HttpStatus.partialContent;
    resp.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (contentType != null) resp.headers.contentType = contentType;
    resp.headers
        .set(HttpHeaders.contentRangeHeader, 'bytes $start-$last/$total');
  }

  Future<void> _relayWholeFile(
    HttpResponse resp,
    _WholeFileRelay relay,
    bool headersWritten,
    bool isHead,
  ) async {
    if (!headersWritten) {
      resp.statusCode = HttpStatus.ok;
      final ct = relay.response.headers.contentType;
      if (ct != null) resp.headers.contentType = ct;
      if (isHead) {
        await relay.response.drain<void>();
        await resp.close();
        return;
      }
      await resp.flush();
    }
    await for (final chunk in relay.response) {
      resp.add(chunk);
      await resp.flush();
    }
  }

  /// Joins or starts the upstream fetch for one block.
  ///
  /// Concurrent relays and the prefetcher share the same future: the observed
  /// field behaviour was 2-4 parallel Range connections pulling identical
  /// blocks, wasting the CDN budget on duplicate bytes.
  Future<_BlockOutcome> _fetchShared(
    _Route route,
    int blockIndex,
    int? total,
  ) {
    final key = _blockKey(route.cacheKey, blockIndex);
    final existing = _inflight[key];
    if (existing != null) return existing;
    _inflightByKey[route.cacheKey] = (_inflightByKey[route.cacheKey] ?? 0) + 1;
    final fetchStartedAt = DateTime.now();
    final future = _fetchBlockWithRecovery(route, blockIndex, total)
        .then((outcome) async {
          if (outcome.bytes != null) {
            // Logcat-visible per-fetch line (the AppLog file is not reachable
            // on a release install): achieved throughput per block is what
            // separates a CDN-throttled stall from a player-side one.
            final fetchMs =
                DateTime.now().difference(fetchStartedAt).inMilliseconds;
            debugPrint(
              'MEDIO-TRANSPORT block #$blockIndex 206 '
              'bytes=${outcome.bytes!.length} total=${fetchMs}ms '
              'route=${route.cacheKey}',
            );
            // Persist before completing: the serving loop may consume the
            // bytes straight from this future, and a second play (or another
            // connection) must find them on disk.
            await cache?.write(route.cacheKey, blockIndex, outcome.bytes!);
            if (outcome.total != null) {
              unawaited(cache?.writeTotal(route.cacheKey, outcome.total!));
            }
            if (!_cacheUsable) _remember(key, outcome);
          }
          return outcome;
        })
        .whenComplete(() {
          _inflight.remove(key);
          final n = (_inflightByKey[route.cacheKey] ?? 1) - 1;
          if (n <= 0) {
            _inflightByKey.remove(route.cacheKey);
          } else {
            _inflightByKey[route.cacheKey] = n;
          }
        });
    _inflight[key] = future;
    return future;
  }

  /// Remembers a completed fetch so a connection that reaches the block after
  /// its future dropped does not re-download it (no-disk-cache setups).
  void _remember(String key, _BlockOutcome outcome) {
    _recent.remove(key);
    _recent[key] = outcome;
    while (_recent.length > _recentCap) {
      _recent.remove(_recent.keys.first);
    }
  }

  /// Returns a recently completed fetch for [key], if any.
  ///
  /// Read-only: several connections may be waiting on the same block, and the
  /// entry is only dropped by the LRU cap in [_remember].
  _BlockOutcome? _takeRecent(String key) => _recent[key];

  /// Starts fetching the blocks after [servedIndex] without waiting for the
  /// player to ask for them.
  void _schedulePrefetch(
    _Route route,
    int servedIndex,
    int? total,
    int? requestedEnd,
  ) {
    // Whole-file upstreams (Range ignored) are relayed as one response;
    // block prefetching does not apply.
    if (route.wholeFileMode) return;
    for (var i = 1; i <= prefetchDepth; i++) {
      final index = servedIndex + i;
      final start = blockStartOffset(index, chunkSize);
      if (total != null && start >= total) break;
      if (requestedEnd != null && start > requestedEnd) break;
      if (_inflight.containsKey(_blockKey(route.cacheKey, index))) continue;
      // A block that already completed (prefetched moments ago) must not be
      // fetched a second time: it is either in `_recent` (no cache) or on
      // disk, and `_inflight` no longer holds it.
      if (_recent.containsKey(_blockKey(route.cacheKey, index))) continue;
      final inFlight = _inflightByKey[route.cacheKey] ?? 0;
      if (inFlight >= maxInflightPerFile) {
        // One line per throttle event: shows when a stream is starved because
        // sibling tracks are holding the whole per-file concurrency budget.
        debugPrint(
          'MEDIO-TRANSPORT prefetch cap reached: inFlight=$inFlight '
          'servedBlock=$servedIndex',
        );
        break;
      }
      unawaited(_prefetchOne(route, index, total));
    }
  }

  Future<void> _prefetchOne(_Route route, int blockIndex, int? total) async {
    try {
      if (_cacheUsable && await cache!.exists(route.cacheKey, blockIndex)) {
        return;
      }
      await _fetchShared(route, blockIndex, total);
    } catch (e) {
      AppLog.instance
          .d('NetdiskTransport', 'prefetch block #$blockIndex failed: $e');
    }
  }

  Future<_BlockOutcome> _fetchBlockWithRecovery(
    _Route route,
    int blockIndex,
    int? total,
  ) async {
    var attempts = 0;
    while (true) {
      final fetch = await _fetchBlock(route, blockIndex, total);
      if (fetch.wholeFile != null) return _BlockOutcome.whole(fetch.wholeFile!);
      if (fetch.bytes != null) {
        return _BlockOutcome.ranged(
          fetch.bytes!,
          fetch.total ?? total,
          fetch.contentType,
        );
      }
      final canRefresh = route.refresh != null &&
          shouldReResolve(
            statusCode: fetch.statusCode,
            connectionFailed: fetch.connectionFailed,
            hasSentBytes: false,
            refreshAttempts: attempts,
            maxRefreshAttempts: maxRefreshAttempts,
          );
      // A signed URL that expired is recovered by going back through the
      // redirecting stream URL: it mints a fresh URL per request, while
      // re-resolving may keep returning the server's cached (dead) redirect for
      // minutes — which is exactly what turned a seek into a 20 s stall.
      if (shouldUseRedirectFallback(
        statusCode: fetch.statusCode,
        connectionFailed: fetch.connectionFailed,
        redirectUrl: route.redirectUrl,
        activeUrl: route.upstreamUrl,
      )) {
        route.upstreamUrl = route.redirectUrl!;
        debugPrint(
          'MEDIO-TRANSPORT upstream expired (${fetch.statusCode}) -> '
          'per-request redirect URL, retrying block=$blockIndex',
        );
        AppLog.instance.w(
          'NetdiskTransport',
          'signed URL expired (${fetch.statusCode}); using per-request '
              'redirect upstream',
        );
        _scheduleRepin(route);
        continue;
      }
      // Per-block logging would be one line per 4 MB (~1–5/s on a 40 Mbps
      // remux), so only the exceptional outcomes are logged; routine throughput
      // already goes to AppLog.
      if (!canRefresh) return _BlockOutcome.failed(fetch.statusCode);
      attempts++;
      debugPrint(
        'MEDIO-TRANSPORT re-resolve #$attempts after '
        '${fetch.statusCode ?? 'connection failure'} block=$blockIndex',
      );
      await Future<void>.delayed(reResolveDelay(attempts));
      try {
        final refreshedAt = DateTime.now();
        final fresh = await route.refresh!();
        debugPrint(
          'MEDIO-TRANSPORT re-resolve #$attempts done in '
          '${DateTime.now().difference(refreshedAt).inMilliseconds}ms',
        );
        route.upstreamUrl = fresh.url;
        if (fresh.headers.isNotEmpty) route.headers = fresh.headers;
        AppLog.instance.i(
          'NetdiskTransport',
          're-resolved after ${fetch.statusCode ?? 'connection failure'} '
              '(attempt $attempts)',
        );
      } catch (e) {
        AppLog.instance.w('NetdiskTransport', 'refresh failed: $e');
        return _BlockOutcome.failed(fetch.statusCode);
      }
    }
  }

  /// Re-pins a freshly resolved CDN URL in the background after falling back to
  /// the redirecting stream URL, so the common path stays on the direct CDN.
  ///
  /// At most once per route: if the re-resolved URL turns out to be stale too
  /// (the server caches its redirect for minutes), the route stays on the
  /// redirecting URL instead of ping-ponging between two dead URLs.
  void _scheduleRepin(_Route route) {
    final refresh = route.refresh;
    if (refresh == null || route.repinned) return;
    route.repinned = true;
    unawaited(
      Future<void>.delayed(const Duration(seconds: 2), () async {
        if (!_routes.containsValue(route)) return;
        try {
          final fresh = await refresh();
          if (!_routes.containsValue(route)) return;
          route.upstreamUrl = fresh.url;
          if (fresh.headers.isNotEmpty) route.headers = fresh.headers;
          debugPrint('MEDIO-TRANSPORT re-pinned CDN upstream after expiry');
        } catch (e) {
          AppLog.instance.w('NetdiskTransport', 're-pin failed: $e');
        }
      }),
    );
  }

  Future<_UpstreamFetch> _fetchBlock(
    _Route route,
    int blockIndex,
    int? total,
  ) async {
    final start = blockStartOffset(blockIndex, chunkSize);
    final end = blockFetchEnd(
      blockIndex: blockIndex,
      blockSize: chunkSize,
      total: total,
    );
    try {
      final request = await route.client.getUrl(Uri.parse(route.upstreamUrl));
      route.headers.forEach(request.headers.set);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      final fetchStartedAt = DateTime.now();
      final upResp = await request.close();
      final headersMs = DateTime.now().difference(fetchStartedAt).inMilliseconds;
      if (upResp.statusCode == HttpStatus.partialContent) {
        final bytes = await _collectBytes(upResp);
        return _UpstreamFetch.ranged(
          bytes,
          _totalFromContentRange(
                  upResp.headers.value(HttpHeaders.contentRangeHeader)) ??
              total,
          upResp.headers.contentType,
        );
      }
      if (upResp.statusCode == HttpStatus.ok) {
        debugPrint(
          'MEDIO-TRANSPORT block #$blockIndex WHOLE-FILE 200 (range ignored)',
        );
        return _UpstreamFetch.wholeFile(_WholeFileRelay(upResp));
      }
      debugPrint(
        'MEDIO-TRANSPORT block #$blockIndex status=${upResp.statusCode} '
        'headers=${headersMs}ms',
      );
      await upResp.drain<void>();
      return _UpstreamFetch.status(upResp.statusCode);
    } catch (e) {
      debugPrint('MEDIO-TRANSPORT block #$blockIndex failed: $e');
      return _UpstreamFetch.connectionFailure();
    }
  }

  static Future<Uint8List> _collectBytes(HttpClientResponse resp) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in resp) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static int? _totalFromContentRange(String? value) {
    if (value == null) return null;
    final slash = value.lastIndexOf('/');
    if (slash < 0) return null;
    final raw = value.substring(slash + 1).trim();
    if (raw == '*') return null;
    return int.tryParse(raw);
  }
}

class _Route {
  _Route({
    required this.upstreamUrl,
    required this.headers,
    required this.cacheKey,
    this.redirectUrl,
    this.refresh,
  });

  String upstreamUrl;
  Map<String, String> headers;
  final String cacheKey;

  /// Stable server stream URL that redirects to a fresh signed URL per request.
  final String? redirectUrl;
  final Future<ResolvedStreamTarget> Function()? refresh;

  /// Whether the background re-pin already ran for this route.
  bool repinned = false;

  /// Set once the upstream answered with a bare 200 (Range ignored): the
  /// stream is then relayed whole and block prefetching is pointless.
  bool wholeFileMode = false;

  HttpClient? _client;

  /// Upstream client shared by every relay and prefetch of this route, so a
  /// TCP connection built for one block is reused by the next, and closing
  /// one relay does not abort fetches the prefetcher is still counting on.
  HttpClient get client => _client ??= HttpClient()
    ..autoUncompress = false
    ..connectionTimeout = NetdiskTransport._connectTimeout;

  /// Aborts this route's upstream fetches (route replaced / shutdown).
  void disposeClient() {
    _client?.close(force: true);
    _client = null;
  }
}

class _WholeFileRelay {
  _WholeFileRelay(this.response);
  final HttpClientResponse response;
}

class _UpstreamFetch {
  _UpstreamFetch.ranged(this.bytes, this.total, this.contentType)
      : wholeFile = null,
        statusCode = null,
        connectionFailed = false;
  _UpstreamFetch.wholeFile(this.wholeFile)
      : bytes = null,
        total = null,
        contentType = null,
        statusCode = null,
        connectionFailed = false;
  _UpstreamFetch.status(this.statusCode)
      : bytes = null,
        total = null,
        contentType = null,
        wholeFile = null,
        connectionFailed = false;
  _UpstreamFetch.connectionFailure()
      : bytes = null,
        total = null,
        contentType = null,
        wholeFile = null,
        statusCode = null,
        connectionFailed = true;

  final Uint8List? bytes;
  final int? total;
  final ContentType? contentType;
  final _WholeFileRelay? wholeFile;
  final int? statusCode;
  final bool connectionFailed;
}

class _BlockOutcome {
  _BlockOutcome.ranged(this.bytes, this.total, this.contentType)
      : wholeFile = null,
        statusCode = null;
  _BlockOutcome.whole(this.wholeFile)
      : bytes = null,
        total = null,
        contentType = null,
        statusCode = null;
  _BlockOutcome.failed(this.statusCode)
      : bytes = null,
        total = null,
        contentType = null,
        wholeFile = null;

  final Uint8List? bytes;
  final int? total;
  final ContentType? contentType;
  final _WholeFileRelay? wholeFile;
  final int? statusCode;
}
