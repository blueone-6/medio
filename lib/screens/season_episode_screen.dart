import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/emby_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_indicator.dart';
import '../utils/media_navigation.dart';
import '../widgets/media_list_tile.dart';

class SeasonEpisodeScreen extends ConsumerWidget {
  const SeasonEpisodeScreen({
    super.key,
    required this.seriesId,
    required this.seasonId,
    this.seasonName,
  });

  /// Reserved for future navigation back to series hub.
  // ignore: unused_field
  final String seriesId;
  final String seasonId;
  final String? seasonName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodes = ref.watch(embyEpisodesProvider(seasonId));

    final emby = ref.watch(embyServiceProvider);

    return Scaffold(
      appBar: AppBar(title: Text(seasonName ?? '剧集')),
      body: episodes.when(
        data: (list) {
          if (list.isEmpty) {
            return const EmptyStateView(
              icon: Icons.tv_off_outlined,
              title: '暂无剧集',
              subtitle: '这一季还没有可播放的分集',
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = list[i];
              final sub = e.runTimeTicks != null
                  ? '第 ${e.indexNumber ?? i + 1} 集'
                  : null;
              return MediaListTile(
                title: e.name,
                subtitle: sub,
                showThumbnail: false,
                leadingLabel: e.indexNumber?.toString() ?? '${i + 1}',
                onTap: () => playMediaFromCard(context, emby, e),
              );
            },
          );
        },
        loading: () => const LoadingIndicator.list(),
        error: (err, _) => ErrorView(
          error: err,
          onRetry: () => ref.invalidate(embyEpisodesProvider(seasonId)),
        ),
      ),
    );
  }
}
