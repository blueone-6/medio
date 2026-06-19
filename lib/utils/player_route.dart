import '../models/emby/emby_media_item.dart';
import '../core/logging/app_log.dart';

/// Builds `/player` route with list/detail resume hints when available.
String playerRouteForItem(String itemId, {EmbyMediaItem? item}) {
  final params = <String, String>{'itemId': itemId};
  if (item != null) {
    final pct = item.userDataPlayedPercentage;
    if (pct != null && pct > 0 && pct < 99.5) {
      params['playedPercentage'] = pct.toString();
    }
    final ticks = item.userDataPlaybackPositionTicks;
    if (ticks != null && ticks > 0) {
      params['positionTicks'] = '$ticks';
    }
    AppLog.instance.i('PlayerRoute', 'itemId=$itemId item=${item.name} '
        'playedPct=$pct positionTicks=$ticks');
  } else {
    AppLog.instance.i('PlayerRoute', 'itemId=$itemId item=NULL (no resume hint)');
  }
  return Uri(path: '/player', queryParameters: params).toString();
}
