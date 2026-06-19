import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/perf.dart';
import '../../models/emby/emby_media_item.dart';
import '../../providers/settings_provider.dart';
import '../empty_state_view.dart';
import '../error_view.dart';
import '../loading_indicator.dart';
import 'tv_library_browse_grid.dart';

/// TV library/movies/series browse with paginated Emby fetches (96 items/page).
class TvPaginatedLibraryBrowse extends ConsumerStatefulWidget {
  const TvPaginatedLibraryBrowse({
    super.key,
    required this.parentId,
    this.includeItemTypes,
    this.allItems,
    this.onBrowseIntoFolder,
  });

  final String parentId;
  final String? includeItemTypes;
  final List<EmbyMediaItem>? allItems;
  final void Function(EmbyMediaItem folder)? onBrowseIntoFolder;

  static const pageSize = 96;
  static const filteredPageSize = 48;

  @override
  ConsumerState<TvPaginatedLibraryBrowse> createState() =>
      _TvPaginatedLibraryBrowseState();
}

class _TvPaginatedLibraryBrowseState
    extends ConsumerState<TvPaginatedLibraryBrowse> {
  final _items = <EmbyMediaItem>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  PerfSpan? _firstPageSpan;

  bool get _filtered =>
      widget.includeItemTypes != null &&
      widget.includeItemTypes!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final syntheticItems = widget.allItems;
    if (syntheticItems != null) {
      _items.addAll(syntheticItems);
      _loading = false;
      _hasMore = false;
      return;
    }
    _firstPageSpan = PerfTracer.start(
      'tv.library.first_page',
      context: {
        'parentId': widget.parentId,
        'types': widget.includeItemTypes ?? '',
      },
    );
    _loadPage(reset: true);
  }

  @override
  void didUpdateWidget(covariant TvPaginatedLibraryBrowse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parentId != widget.parentId ||
        oldWidget.includeItemTypes != widget.includeItemTypes ||
        oldWidget.allItems != widget.allItems) {
      _firstPageSpan?.end(extraContext: {'first_page_via': 'cancelled'});
      final syntheticItems = widget.allItems;
      if (syntheticItems != null) {
        setState(() {
          _items
            ..clear()
            ..addAll(syntheticItems);
          _loading = false;
          _loadingMore = false;
          _hasMore = false;
          _error = null;
        });
        return;
      }
      _firstPageSpan = PerfTracer.start(
        'tv.library.first_page',
        context: {
          'parentId': widget.parentId,
          'types': widget.includeItemTypes ?? '',
        },
      );
      _loadPage(reset: true);
    }
  }

  Future<void> _loadPage({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _hasMore = true;
        _items.clear();
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final emby = ref.read(embyServiceProvider);
      final batch = await emby.getItems(
        parentId: widget.parentId,
        startIndex: reset ? 0 : _items.length,
        limit: _filtered
            ? TvPaginatedLibraryBrowse.filteredPageSize
            : TvPaginatedLibraryBrowse.pageSize,
        includeItemTypes: widget.includeItemTypes,
        recursive: _filtered,
        sortBy: _filtered ? 'SortName' : null,
        sortOrder: _filtered ? 'Ascending' : null,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(batch);
        } else {
          _items.addAll(batch);
        }
        final pageSize = _filtered
            ? TvPaginatedLibraryBrowse.filteredPageSize
            : TvPaginatedLibraryBrowse.pageSize;
        _hasMore = batch.length >= pageSize;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      if (reset) {
        _firstPageSpan?.end(extraContext: {'count': batch.length});
        _firstPageSpan = null;
      }
    } catch (e, st) {
      if (!mounted) return;
      _firstPageSpan?.endError(e, st);
      _firstPageSpan = null;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e;
      });
    }
  }

  void _onNearEnd() {
    if (_loading || _loadingMore || !_hasMore) return;
    _loadPage(reset: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const LoadingIndicator.posterGrid(homeRecommendStyle: true);
    }
    if (_error != null && _items.isEmpty) {
      return ErrorView(
        error: _error,
        onRetry: () => _loadPage(reset: true),
      );
    }
    if (_items.isEmpty) {
      return EmptyStateView(
        icon: Icons.video_library_outlined,
        title: '暂无内容',
        subtitle: '此文件夹下还没有可浏览的条目',
        actionLabel: '刷新',
        onAction: () => _loadPage(reset: true),
      );
    }

    return TvLibraryBrowseGrid(
      items: _items,
      emby: ref.read(embyServiceProvider),
      loadingMore: _loadingMore,
      hasMore: _hasMore,
      onNearEnd: _onNearEnd,
      onBrowseIntoFolder: widget.onBrowseIntoFolder,
    );
  }
}
