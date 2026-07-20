import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/emby/emby_library.dart';
import '../../providers/emby_provider.dart';
import '../../services/emby_service.dart';
import '../skeleton.dart';
import 'home_layout.dart';
import 'home_section_header.dart';
import 'home_typography.dart';
import 'recommendation_section.dart';

/// 桌面首页媒体库区：每个库的「最新内容」海报行（标题/查看全部进入该库）。
class HomePcLibrarySections extends StatelessWidget {
  const HomePcLibrarySections({
    super.key,
    required this.libraries,
    required this.emby,
    required this.onOpenLibrary,
  });

  final List<EmbyLibrary> libraries;
  final EmbyService emby;
  final void Function(EmbyLibrary library) onOpenLibrary;

  static const _browsableTypes = {'movies', 'tvshows', 'mixed'};
  static const _maxLatestRows = 5;

  static bool _isBrowsable(EmbyLibrary lib) {
    final t = lib.collectionType?.trim().toLowerCase();
    return t == null || _browsableTypes.contains(t);
  }

  @override
  Widget build(BuildContext context) {
    final browsable =
        libraries.where(_isBrowsable).take(_maxLatestRows).toList();
    if (browsable.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < browsable.length; i++) ...[
          if (i > 0) const SizedBox(height: HomeLayout.pcSectionGap),
          HomePcLibraryLatestRow(
            library: browsable[i],
            emby: emby,
            onOpenLibrary: () => onOpenLibrary(browsable[i]),
          ),
        ],
      ],
    );
  }
}

/// 单个媒体库的「最新内容」海报行：标题可点击进库，横排最新 12 条。
class HomePcLibraryLatestRow extends ConsumerWidget {
  const HomePcLibraryLatestRow({
    super.key,
    required this.library,
    required this.emby,
    required this.onOpenLibrary,
  });

  static const posterWidth = 132.0;
  static double get rowHeight =>
      posterWidth / HomeLayout.recommendPosterAspectRatio;

  final EmbyLibrary library;
  final EmbyService emby;
  final VoidCallback onOpenLibrary;

  EmbyLibraryListArg get _query {
    final t = library.collectionType?.trim().toLowerCase();
    final types = switch (t) {
      'movies' => 'Movie',
      'tvshows' => 'Series',
      _ => null,
    };
    return (
      parentId: library.id,
      includeItemTypes: types,
      recursive: true,
      limit: 12,
      sortBy: 'DateCreated',
      sortOrder: 'Descending',
      searchTerm: null,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(embyLibraryItemsProvider(_query));

    final items = async.value;
    if (items != null && items.isEmpty) return const SizedBox.shrink();
    if (async.hasError && items == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          title: library.name,
          titleStyle: HomeTypography.headlineLg(cs.onSurface),
          onTitleTap: onOpenLibrary,
          trailingLabel: '查看全部',
          onTrailingTap: onOpenLibrary,
        ),
        const SizedBox(height: HomeLayout.sectionHeaderGap),
        SizedBox(
          height: rowHeight,
          child: items == null
              ? ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 8,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: HomeLayout.gridGap),
                  itemBuilder: (_, __) => const SizedBox(
                    width: posterWidth,
                    child: Skeleton(borderRadius: HomeLayout.cardRadiusR),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: HomeLayout.gridGap),
                  itemBuilder: (context, i) => SizedBox(
                    width: posterWidth,
                    child: HomeRecommendCard(
                      item: items[i],
                      emby: emby,
                      useHomeTypography: true,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
