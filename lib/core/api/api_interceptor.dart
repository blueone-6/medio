import 'dart:io';

import 'package:dio/dio.dart';

import '../../config/app_config.dart';
import '../logging/app_log.dart';
import '../logging/perf.dart';
import 'api_exception.dart';

/// Logs every Dio request through [AppLog] (so it lands in the rotated log
/// file even in release builds) and records a [PerfSpan] for each call —
/// duration ends up in the diagnostics ring buffer.
///
/// `Authorization` / `X-Emby-Token` / `X-Emby-Authorization` are redacted.
class LoggingInterceptor extends Interceptor {
  static const _spanKey = '__perf_span';
  static const _redacted = {'Authorization', 'X-Emby-Token', 'X-Emby-Authorization'};
  static const _bodyMaxLen = 800;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final span = PerfTracer.start(
      'http.${options.method.toLowerCase()}',
      context: {
        'host': options.uri.host,
        'path': options.uri.path,
      },
    );
    options.extra[_spanKey] = span;

    final headers = Map<String, dynamic>.from(options.headers);
    for (final key in _redacted) {
      if (headers.containsKey(key)) headers[key] = '***';
    }
    AppLog.instance.d(
      'HTTP',
      '→ ${options.method} ${options.uri}',
      'headers=$headers'
      '${(options.method != 'GET' && options.method != 'DELETE' && options.data != null) ? ' body=${dataTruncated(options.data)}' : ''}',
    );
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final span = response.requestOptions.extra[_spanKey];
    if (span is PerfSpan) {
      span.end(extraContext: {'status': response.statusCode});
    }
    AppLog.instance.i(
      'HTTP',
      '← ${response.requestOptions.method} ${response.requestOptions.uri} '
      '→ ${response.statusCode}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final span = err.requestOptions.extra[_spanKey];
    if (span is PerfSpan) {
      span.endError(err, err.stackTrace);
    }
    final req = err.requestOptions;
    AppLog.instance.w(
      'HTTP',
      '✗ ${req.method} ${req.uri} '
      '→ ${err.response?.statusCode ?? 'N/A'} ${err.message ?? ''}',
      err.response?.data,
    );
    handler.next(err);
  }

  /// Truncate large request bodies to avoid flooding the log file.
  static String dataTruncated(dynamic data, {int maxLen = _bodyMaxLen}) {
    final s = data.toString();
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}… (${s.length} chars)';
  }
}

/// Retries idempotent GET and transient network failures (incl. POST PlaybackInfo).
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio, {this.maxRetries = AppConfig.maxNetworkRetries});

  final Dio _dio;
  final int maxRetries;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    if (!_canRetry(req, err)) {
      handler.next(err);
      return;
    }
    final attempt = (req.extra['retry_attempt'] as int?) ?? 0;
    if (attempt >= maxRetries) {
      handler.next(err);
      return;
    }
    req.extra['retry_attempt'] = attempt + 1;
    final delayMs = 400 * (1 << attempt);
    AppLog.instance.w(
      'HTTP',
      'retry ${req.method} ${req.uri} attempt=${attempt + 1}/$maxRetries '
      'after ${delayMs}ms (${err.message ?? err.type})',
    );
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    try {
      final response = await _dio.fetch(req);
      handler.resolve(response);
    } catch (e) {
      handler.next(err);
    }
  }

  bool _canRetry(RequestOptions req, DioException err) {
    if (_shouldNotRetry(err)) return false;
    if (req.method == 'GET') return true;
    if (req.method == 'POST' || req.method == 'PUT') {
      return _isTransientNetworkError(err);
    }
    return false;
  }

  bool _isTransientNetworkError(DioException err) => isTransientNetworkError(err);

  bool _shouldNotRetry(DioException err) {
    final code = err.response?.statusCode;
    if (code != null && code >= 400 && code < 500 && code != 408) return true;
    return err.type == DioExceptionType.cancel;
  }
}

/// 连接层失败（超时、握手、无法连接等），可尝试切换协议重连。
bool isTransientNetworkError(DioException err) {
  switch (err.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return true;
    case DioExceptionType.unknown:
      break;
    default:
      return false;
  }
  final cause = err.error;
  if (cause is HandshakeException || cause is SocketException) return true;
  final msg = '${err.message ?? ''} ${cause ?? ''}'.toLowerCase();
  return msg.contains('handshake') ||
      msg.contains('connection terminated') ||
      msg.contains('connection reset') ||
      msg.contains('broken pipe');
}

Never throwApiException(DioException e) {
  final status = e.response?.statusCode;
  final data = e.response?.data;
  String message = e.message ?? 'Network error';
  if (e.error is HandshakeException ||
      message.toLowerCase().contains('handshake')) {
    message = '与服务器的安全连接失败，请检查网络后重试';
  } else if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout) {
    message = '连接超时，请检查网络后重试';
  } else if (e.type == DioExceptionType.connectionError) {
    message = '无法连接服务器，请检查网络与地址';
  }
  if (data is Map && data['Message'] is String) {
    message = data['Message'] as String;
  } else if (data is String && data.isNotEmpty) {
    message = data;
  }
  throw ApiException(message, statusCode: status, cause: e);
}
