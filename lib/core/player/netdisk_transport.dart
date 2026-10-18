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

  static const Duration _connectTimeout = Duration(seconds: 15);
  static const int maxRefreshAttempts = 2;

  HttpServer? _server;
  int _nextRouteId = 1;
  final Map<String, _Route> _routes = {};

  /// Disk block cache; null (or a disabled cache) means no persistence.
  NetdiskBlockCache? cache;

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
  void unregister(String localUrl) {
    final segments = Uri.tryParse(localUrl)?.pathSegments;
    if (segments == null || segments.isEmpty) return;
    if (_routes.remove(segments.first) != null) {
      AppLog.instance
          .d('NetdiskTransport', 'route ${segments.first} unregistered');
    }
  }

  /// Closes the localhost server and clears all routes (shutdown / tests).
  Future<void> dispose() async {
    _routes.clear();
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
      'MEDIO-TRANSPORT relay #$relayId start range='
      '${req.headers.value(HttpHeaders.rangeHeader) ?? '-'}',
    );
    const throughputLogEveryBytes = 32 * 1024 * 1024;
    const slowBlockFetchThresholdMs = 1500;

    int? total;
    ContentType? contentType;
    var headersWritten = false;
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = _connectTimeout;

    try {
      while (true) {
        if (total != null && pos >= total) break;
        if (requestedEnd != null && pos > requestedEnd) break;

        final blockIndex = pos ~/ chunkSize;
        final blockStart = blockStartOffset(blockIndex, chunkSize);

        var block = await cache?.read(route.cacheKey, blockIndex);
        final fromCache = block != null;

        // A cache hit has no upstream response to read `total` from, so recover
        // it from the cached metadata. Without a known total the response would
        // be a bare 200 (no Content-Range) and mpv would treat the localhost
        // stream as non-seekable ("Cannot seek in this stream.").
        if (block != null && total == null) {
          total = await cache?.readTotal(route.cacheKey);
        }

        if (block == null || total == null) {
          final fetchStartedAt = DateTime.now();
          final outcome =
              await _fetchBlockWithRecovery(route, blockIndex, total, client);
          final fetchMs = DateTime.now().difference(fetchStartedAt).inMilliseconds;
          final relay = outcome.wholeFile;
          if (relay != null) {
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
            if (outcome.total != null) {
              total = outcome.total;
              unawaited(cache?.writeTotal(route.cacheKey, total!));
            }
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
        if (!fromCache && cache != null) {
          await cache!.write(route.cacheKey, blockIndex, data);
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
      client.close(force: true);
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

  Future<_BlockOutcome> _fetchBlockWithRecovery(
    _Route route,
    int blockIndex,
    int? total,
    HttpClient client,
  ) async {
    var attempts = 0;
    while (true) {
      final fetch = await _fetchBlock(route, blockIndex, total, client);
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
    HttpClient client,
  ) async {
    final start = blockStartOffset(blockIndex, chunkSize);
    final end = blockFetchEnd(
      blockIndex: blockIndex,
      blockSize: chunkSize,
      total: total,
    );
    try {
      final request = await client.getUrl(Uri.parse(route.upstreamUrl));
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
