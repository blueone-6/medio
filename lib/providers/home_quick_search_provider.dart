import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emby/emby_media_item.dart';
import '../models/emby/emby_search_result.dart';
import '../utils/emby_item_type.dart';
import 'home_hub_section_provider.dart';
import 'settings_provider.dart';

/// 首页侧边栏快速搜索：Hints → Items 子串 → 已加载首页列表本地模糊匹配。
final homeQuickSearchProvider =
    FutureProvider.family<List<EmbySearchHint>, String>((ref, q) async {
  final term = q.trim();
  if (term.isEmpty) return [];
  final emby = ref.read(embyServiceProvider);
  var hints = await emby.searchHints(term, limit: 100);
  if (hints.isEmpty) {
    hints = _localQuickSearchHints(ref, term);
  }
  return hints;
});

/// 服务端无结果时，在已缓存的首页分区条目里做子串模糊匹配（含单字如「光」）。
List<EmbySearchHint> _localQuickSearchHints(Ref ref, String term) {
  final seen = <String>{};
  final out = <EmbySearchHint>[];
  void addFrom(Iterable<EmbyMediaItem> items) {
    for (final m in items) {
      if (!isEmbyCatalogMediaType(m.type)) continue;
      if (!embyFieldsMatchSearchTerm([m.name, m.seriesName], term)) continue;
      if (!seen.add(m.id)) continue;
      out.add(EmbySearchHint(item: m));
    }
  }

  for (final key in ['series', 'movie']) {
    addFrom(ref.read(homeHubSectionProvider(key)).items);
  }
  return out;
}
