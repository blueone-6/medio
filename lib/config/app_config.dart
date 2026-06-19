import 'app_features.dart';

/// Global app constants.
abstract final class AppConfig {
  static const String appName = AppFeatures.appName;

  /// Emby `X-Emby-Authorization` → `Client="..."` (must be non-empty).
  static const String embyClientName = appName;

  /// Sent in `Version="..."` for Emby session / auth.
  static const String embyClientVersion = '1.0.0+3';

  /// Dio timeouts.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 60);

  /// GET + transient network retries (handshake / connection reset).
  static const int maxNetworkRetries = 3;

  /// Grid columns for media (non-TV).
  static const int mediaGridCrossAxisCount = 3;

  /// Thumbnail size hint for Emby image URLs.
  static const int posterMaxHeight = 320;

  /// 首页「最近播放」等横滑条：固定海报高度，多卡底边对齐。
  static const double homeRecentStripPosterHeight = 172;

  /// Shared HTTP User-Agent for playback & poster CDN requests.
  static const String httpUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
}
