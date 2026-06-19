import '../core/player/external_cdn_headers.dart';
import '../models/emby/emby_playback_info.dart';

Map<String, String>? playbackHttpHeaders(
  String url, {
  String? embyServerBase,
  String? embyToken,
}) {
  if (isExternalCdnPlaybackUrl(url)) {
    return externalCdnPlaybackHttpHeaders();
  }

  if (embyServerBase != null &&
      embyToken != null &&
      embyToken.isNotEmpty &&
      isEmbyHostedStreamUrl(url, embyServerBase)) {
    return {'X-Emby-Token': embyToken};
  }

  return null;
}
