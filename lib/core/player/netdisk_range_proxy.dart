import 'dart:async';
import 'dart:io';

import '../logging/app_log.dart';

/// Localhost HTTP proxy that rewrites progressive (open-ended) playback
/// requests into **bounded** byte-range requests.
///
/// Some netdisk CDNs (notably Quark's `*.drive.quark.cn`) throttle whole-file /
/// open-ended transfers to a crawl (~100 KB/s) while serving explicit
/// `Range: bytes=start-end` requests at full speed. libmpv/libavformat and
/// ExoPlayer both stream progressively (open-ended), so 4K content starves and
/// playback stutters.
///
/// This proxy sits between the player and the CDN: the player opens a normal
/// localhost HTTP URL, and the proxy serves it a continuous stream assembled
/// from bounded upstream range requests.
///
/// The direct CDN URL (which carries a signed, time-limited token) stays inside
/// the registration and is never handed to the player, so it does not end up in
/// player logs. Routes are dropped on [unregister].
class NetdiskRangeProxy {
  NetdiskRangeProxy._();

  static final NetdiskRangeProxy instance = NetdiskRangeProxy._();

  /// Upstream chunk size. Large enough to keep per-request overhead
  /// negligible, small enough that the CDN treats each request as a bounded
  /// range rather than a whole-file download.
  static const int chunkSize = 4 * 1024 * 1024;

  static const Duration _connectTimeout = Duration(seconds: 15);

  HttpServer? _server;
  int _port = 0;
  int _nextRouteId = 1;
  final Map<String, _ProxyRoute> _routes = {};

  /// Registers [upstreamUrl] (fetched with [headers]) and returns the localhost
  /// URL the player should open. Call [unregister] with the returned URL when
  /// playback moves on.
  Future<String> register({
    required String upstreamUrl,
    Map<String, String>? headers,
  }) async {
    final server = await _ensureServer();
    final id = '${_nextRouteId++}';
    _routes[id] = _ProxyRoute(upstreamUrl, headers ?? const {});
    final local = 'http://127.0.0.1:${server.port}/$id';
    AppLog.instance.i('NetdiskProxy', 'route $id registered (proxy=$local)');
    return local;
  }

  /// Drops the route behind [localUrl], if any.
  void unregister(String localUrl) {
    final segments = Uri.tryParse(localUrl)?.pathSegments;
    if (segments == null || segments.isEmpty) return;
    final id = segments.first;
    if (_routes.remove(id) != null) {
      AppLog.instance.d('NetdiskProxy', 'route $id unregistered');
    }
  }

  /// Closes the localhost server and clears all routes (app shutdown / tests).
  Future<void> dispose() async {
    _routes.clear();
    final server = _server;
    _server = null;
    _port = 0;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    _server = server;
    _port = server.port;
    server.listen(
      (req) => unawaited(_onRequest(req)),
      onError: (Object e) =>
          AppLog.instance.w('NetdiskProxy', 'server error: $e'),
    );
    AppLog.instance.i('NetdiskProxy', 'listening on 127.0.0.1:$_port');
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

  Future<void> _stream(HttpRequest req, _ProxyRoute route) async {
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = _connectTimeout;
    final resp = req.response;
    final isHead = req.method == 'HEAD';

    var start = 0;
    int? requestedEnd;
    final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      final m = RegExp(r'bytes=(\d+)-(\d+)?').firstMatch(rangeHeader);
      if (m != null) {
        start = int.tryParse(m.group(1)!) ?? 0;
        final e = m.group(2);
        if (e != null) requestedEnd = int.tryParse(e);
      }
    }

    int? total;
    var pos = start;
    var headersWritten = false;
    AppLog.instance.d(
      'NetdiskProxy',
      'client range start=$start end=${requestedEnd ?? 'eof'}',
    );
    try {
      while (true) {
        if (total != null && pos >= total) break;
        if (requestedEnd != null && pos > requestedEnd) break;

        var end = pos + chunkSize - 1;
        if (requestedEnd != null && end > requestedEnd) end = requestedEnd;

        final up = await client.getUrl(Uri.parse(route.upstreamUrl));
        route.headers.forEach(up.headers.set);
        // Video bytes must not be transparently gzipped.
        up.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        up.headers.set(HttpHeaders.rangeHeader, 'bytes=$pos-$end');
        final upResp = await up.close();

        final isPartial = upResp.statusCode == HttpStatus.partialContent;
        if (!headersWritten) {
          if (isPartial) {
            total = _totalFromContentRange(
              upResp.headers.value(HttpHeaders.contentRangeHeader),
            );
            resp.statusCode = HttpStatus.partialContent;
            resp.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
            final ct = upResp.headers.contentType;
            if (ct != null) resp.headers.contentType = ct;
            if (total != null) {
              final last = requestedEnd ?? (total - 1);
              resp.headers.set(
                HttpHeaders.contentRangeHeader,
                'bytes $start-$last/$total',
              );
            }
          } else {
            // Upstream ignored the range and returned the whole file from 0.
            resp.statusCode = upResp.statusCode;
            final ct = upResp.headers.contentType;
            if (ct != null) resp.headers.contentType = ct;
          }
          headersWritten = true;
          if (isHead) {
            await upResp.drain<void>();
            await resp.close();
            return;
          }
          await resp.flush();
        }

        var got = 0;
        await for (final data in upResp) {
          resp.add(data);
          got += data.length;
          await resp.flush();
        }

        if (!isPartial) break; // whole-file response streamed once
        if (got == 0) break; // upstream gave nothing new
        pos += got;
        if (total == null) break;
        if (pos >= total) break;
        if (requestedEnd != null && pos > requestedEnd) break;
      }
    } catch (e) {
      AppLog.instance.d('NetdiskProxy',
          'stream ended (client=${req.connectionInfo?.remoteAddress.address}): $e');
    } finally {
      client.close(force: true);
      try {
        await resp.close();
      } catch (_) {}
    }
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

class _ProxyRoute {
  _ProxyRoute(this.upstreamUrl, this.headers);
  final String upstreamUrl;
  final Map<String, String> headers;
}
