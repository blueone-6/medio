import '../models/emby/emby_media_item.dart';
import '../models/home_browse.dart';

/// Heuristic region buckets from [EmbyMediaItem.productionLocations] and name.
bool homeRegionMatches(EmbyMediaItem item, HomeRegionFilter region) {
  final loc = (item.productionLocations ?? const <String>[])
      .join(' ')
      .toLowerCase();
  final blob = '$loc ${item.name}'.toLowerCase();

  bool hasAny(Iterable<String> keys) => keys.any((k) => blob.contains(k));

  switch (region) {
    case HomeRegionFilter.none:
      return true;
    case HomeRegionFilter.mandarin:
      return hasAny([
        'china',
        'chinese',
        '中国',
        '台湾',
        'taiwan',
        'hong kong',
        '香港',
        'singapore',
        '新加坡',
        'macau',
        '澳门',
      ]);
    case HomeRegionFilter.western:
      if (homeRegionMatches(item, HomeRegionFilter.mandarin) ||
          homeRegionMatches(item, HomeRegionFilter.korea) ||
          homeRegionMatches(item, HomeRegionFilter.japan)) {
        return false;
      }
      return hasAny([
        'united states',
        'usa',
        'u.s.',
        'united kingdom',
        'uk',
        'france',
        'germany',
        'canada',
        'australia',
        'italy',
        'spain',
        'sweden',
        'norway',
        '美国',
        '英国',
        '法国',
        '德国',
        '加拿大',
        '澳大利亚',
      ]);
    case HomeRegionFilter.korea:
      return hasAny(['korea', 'south korea', '韩国']);
    case HomeRegionFilter.japan:
      return hasAny(['japan', '日本']);
  }
}
