import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../core/theme/app_spacing.dart';
import '../models/emby/emby_media_item.dart';
import '../providers/emby_provider.dart';
import '../providers/recent_play_provider.dart';
import '../providers/settings_provider.dart';
import '../services/emby_service.dart';
import '../utils/media_navigation.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/media_list_tile.dart';

class RecentPlayScreen extends ConsumerStatefulWidget {
  const RecentPlayScreen({super.key});

  @override
  ConsumerState<RecentPlayScreen> createState() => _RecentPlayScreenState();
}

class _RecentPlayScreenState extends ConsumerState<RecentPlayScreen> {
  RecentPlayFilter _filter = RecentPlayFilter.all;

  Future<void> _onRefresh() async {
    ref.invalidate(embyResumeProvider);
    await ref.read(embyResumeProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final emby = ref.watch(embyServiceProvider);
    final limit = ref.watch(settingsServiceProvider).homeRecentPlayLimit;
    final itemsAsync = ref.watch(recentPlayFilteredProvider(_filter));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('最近播放'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(child: _FilterTabs(selected: _filter, onChanged: (f) => setState(() => _filter = f))),
                Text(
                  '最多 $limit 条',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: itemsAsync.when(
              loading: () => const LoadingIndicator.list(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(embyResumeProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.history,
                    title: _emptyLabel(_filter),
                    subtitle: '开始观看后，记录会显示在这里',
                  );
                }
                return RefreshIndicator(
                  onRefresh: _onRefresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _RecentPlayTile(
                      item: items[i],
                      emby: emby,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _emptyLabel(RecentPlayFilter filter) {
    switch (filter) {
      case RecentPlayFilter.series:
        return '暂无电视剧播放记录';
      case RecentPlayFilter.movie:
        return '暂无电影播放记录';
      case RecentPlayFilter.all:
        return '暂无最近播放';
    }
  }
}

class _RecentPlayTile extends StatelessWidget {
  const _RecentPlayTile({required this.item, required this.emby});

  final EmbyMediaItem item;
  final EmbyService emby;

  @override
  Widget build(BuildContext context) {
    final url = emby.backdropUrlForItem(item) ??
        emby.posterUrlForItem(item, maxHeight: AppConfig.posterMaxHeight);
    final isSeries = item.isRecentPlaySeriesItem;

    return MediaListTile(
      title: isSeries ? item.mediaCardSeriesSeasonLine : item.name,
      titleBlock2: isSeries ? item.mediaCardEpisodeLine : null,
      subtitle: item.recentPlayListSubtitle(),
      imageUrl: url,
      httpHeaders: emby.imageAuthHeaders,
      onTap: () => playMediaFromCard(context, emby, item),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.selected, required this.onChanged});

  final RecentPlayFilter selected;
  final ValueChanged<RecentPlayFilter> onChanged;

  static const _labels = {
    RecentPlayFilter.all: '全部',
    RecentPlayFilter.series: '电视剧',
    RecentPlayFilter.movie: '电影',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: RecentPlayFilter.values.map((f) {
        final isSelected = f == selected;
        return Padding(
          padding: EdgeInsets.only(right: f == RecentPlayFilter.movie ? 0 : AppSpacing.md),
          child: GestureDetector(
            onTap: () => onChanged(f),
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _labels[f]!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 2,
                  width: isSelected ? 20 : 0,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
