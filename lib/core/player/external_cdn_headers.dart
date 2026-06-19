import '../../config/app_config.dart';

const _externalCdnReferer = 'https://115.com/';

/// True for 115 pickcode CDN hosts (e.g. cdnfhnfile.115cdn.net).
bool isExternalCdnPlaybackUrl(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return host.contains('115cdn') || host == '115.com' || host.endsWith('.115.com');
}

/// Headers for 115 pickcode CDN playback.
///
/// These are also useful when opening an Emby `/stream` URL that 302/307
/// redirects to 115 CDN, so the followed CDN request keeps the expected
/// hotlink context.
Map<String, String> externalCdnPlaybackHttpHeaders() => {
      'Referer': _externalCdnReferer,
      'Origin': _externalCdnReferer,
      'User-Agent': AppConfig.httpUserAgent,
    };

/// Default Referer/Origin used by mpv when forced fallback is needed.
String get externalCdnRefererFallback => _externalCdnReferer;
