import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../core/player/external_cdn_headers.dart';

Dio? _redirectDio;

Dio get _dio {
  _redirectDio ??= Dio(
    BaseOptions(
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
    ),
  );
  return _redirectDio!;
}

const playbackRedirectMaxHops = 5;

Future<String> resolveHttpRedirectUrl(
  String url, {
  Map<String, String>? requestHeaders,
}) async {
  return resolvePlaybackRedirectChain(
    url,
    requestHeaders: requestHeaders,
    maxHops: 1,
  );
}

Future<String> resolvePlaybackRedirectChain(
  String url, {
  Map<String, String>? requestHeaders,
  String Function(String url)? remapUrl,
  int maxHops = playbackRedirectMaxHops,
}) async {
  final dio = _dio;
  dio.options.headers = requestHeaders ?? {};

  var current = url;
  for (var hop = 0; hop < maxHops; hop++) {
    if (remapUrl != null) {
      current = remapUrl(current);
    }
    if (isExternalCdnPlaybackUrl(current)) return current;

    final next = await _fetchRedirectLocation(dio, current);
    if (next == null || next == current) return current;
    current = next;
    if (isExternalCdnPlaybackUrl(current)) return current;
  }

  return remapUrl != null ? remapUrl(current) : current;
}

Future<String?> _fetchRedirectLocation(Dio dio, String url) async {
  String? locationFrom(Response<dynamic> response) =>
      response.headers.value('location') ?? response.headers.value('Location');

  bool isRedirect(int? code) =>
      code == 301 || code == 302 || code == 303 || code == 307 || code == 308;

  String? pickLocation(Response<dynamic> response) {
    if (!isRedirect(response.statusCode)) return null;
    final loc = locationFrom(response);
    if (loc == null || loc.isEmpty) return null;
    return _absolutize(url, loc);
  }

  String? pickLocationFromError(DioException e) {
    final res = e.response;
    if (res == null) return null;
    return pickLocation(res);
  }

  try {
    final res = await dio.get<ResponseBody>(
      url,
      options: Options(
        followRedirects: false,
        validateStatus: (_) => true,
        responseType: ResponseType.stream,
      ),
    );
    final loc = pickLocation(res);
    final sub = res.data?.stream.listen((_) {});
    await sub?.cancel();
    if (loc != null) return loc;
  } on DioException catch (e) {
    final loc = pickLocationFromError(e);
    if (loc != null) return loc;
  }

  return null;
}

String _absolutize(String base, String location) {
  if (location.startsWith('http://') || location.startsWith('https://')) {
    return location;
  }
  return Uri.parse(base).resolve(location).toString();
}
