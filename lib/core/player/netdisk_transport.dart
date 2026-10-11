import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
  Future<String> register({
    required String upstreamUrl,
    Map<String, String>? headers,
    required String cacheKey,
    Future<ResolvedStreamTarget> Function()? refresh,
  }) async {
    final server = await _ensureServer();
    final id = '${_nextRouteId++}';
    _routes[id] = _Route(
      upstreamUrl: upstreamUrl,
      headers: headers ?? const {},
      cacheKey: cacheKey,
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
          final outcome =
              await _fetchBlockWithRecovery(route, blockIndex, total, client);
          final relay = outcome.wholeFile;
          if (relay != null) {
            return await _relayWholeFile(resp, relay, headersWritten, isHead);
          }
          if (outcome.bytes == null) {
            if (block == null) break;
          } else {
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

        if (total != null && pos >= total) break;
        if (data.length < chunkSize) break;
      }
    } catch (e) {
      AppLog.instance.d('NetdiskTransport', 'stream ended: $e');
    } finally {
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
      if (!canRefresh) return _BlockOutcome.failed(fetch.statusCode);
      attempts++;
      await Future<void>.delayed(reResolveDelay(attempts));
      try {
        final fresh = await route.refresh!();
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
      final upResp = await request.close();
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
        return _UpstreamFetch.wholeFile(_WholeFileRelay(upResp));
      }
      await upResp.drain<void>();
      return _UpstreamFetch.status(upResp.statusCode);
    } catch (e) {
      AppLog.instance.d('NetdiskTransport', 'upstream fetch failed: $e');
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
    this.refresh,
  });

  String upstreamUrl;
  Map<String, String> headers;
  final String cacheKey;
  final Future<ResolvedStreamTarget> Function()? refresh;
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
