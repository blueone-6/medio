import '../../config/app_config.dart';

const _cdnReferer115 = 'https://115.com/';

/// Which netdisk CDN a playback URL points at.
///
/// Each provider enforces a different hotlink policy: 115 requires its own
/// `Referer`/`Origin`, while Quark's CDN rejects requests carrying a `Referer`
/// (`403 denied by Referer ACL`) and only accepts the plain bytes request.
enum ExternalCdnKind {
  none,
  p115,
  quark,
}

/// Classifies [url] by its CDN host. Returns [ExternalCdnKind.none] for the
/// Emby server itself, docker service URLs (`openlist`), and unknown hosts.
ExternalCdnKind classifyExternalCdnUrl(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return ExternalCdnKind.none;
  if (host.contains('115cdn') || host == '115.com' || host.endsWith('.115.com')) {
    return ExternalCdnKind.p115;
  }
  if (host == 'quark.cn' || host.endsWith('.quark.cn')) {
    return ExternalCdnKind.quark;
  }
  return ExternalCdnKind.none;
}

/// True for 115 pickcode CDN hosts (e.g. cdnfhnfile.115cdn.net) and Quark
/// drive CDN hosts (e.g. dl-c-zb-u.drive.quark.cn).
bool isExternalCdnPlaybackUrl(String url) =>
    classifyExternalCdnUrl(url) != ExternalCdnKind.none;

/// True for 115 pickcode CDN hosts.
bool is115CdnPlaybackUrl(String url) =>
    classifyExternalCdnUrl(url) == ExternalCdnKind.p115;

/// True for Quark drive CDN hosts.
bool isQuarkCdnPlaybackUrl(String url) =>
    classifyExternalCdnUrl(url) == ExternalCdnKind.quark;

/// Headers mpv must send for [url]'s CDN.
///
/// - 115: hotlink `Referer`/`Origin` plus the shared UA (the signed URL is
///   bound to the resolving UA).
/// - Quark: UA only — adding a `Referer` makes its CDN answer 403.
/// - Unknown/Emby-hosted: no override.
Map<String, String> externalCdnPlaybackHttpHeadersForUrl(String url) {
  switch (classifyExternalCdnUrl(url)) {
    case ExternalCdnKind.p115:
      return _p115PlaybackHttpHeaders();
    case ExternalCdnKind.quark:
      return _quarkPlaybackHttpHeaders();
    case ExternalCdnKind.none:
      return const {};
  }
}

/// Headers for 115 pickcode CDN playback.
///
/// These are also useful when opening an Emby `/stream` URL that 302/307
/// redirects to 115 CDN, so the followed CDN request keeps the expected
/// hotlink context.
Map<String, String> externalCdnPlaybackHttpHeaders() =>
    _p115PlaybackHttpHeaders();

Map<String, String> _p115PlaybackHttpHeaders() => {
      'Referer': _cdnReferer115,
      'Origin': _cdnReferer115,
      'User-Agent': AppConfig.httpUserAgent,
    };

/// Quark's CDN rejects any request that carries a `Referer`
/// (`X-Tengine-Error: denied by Referer ACL`), so only the User-Agent is sent.
Map<String, String> _quarkPlaybackHttpHeaders() => {
      'User-Agent': AppConfig.httpUserAgent,
    };

/// Default Referer/Origin used by mpv when forced fallback is needed.
String get externalCdnRefererFallback => _cdnReferer115;
