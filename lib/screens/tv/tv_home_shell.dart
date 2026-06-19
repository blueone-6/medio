import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/emby/emby_library.dart';
import '../../models/emby/emby_media_item.dart';
import '../../services/emby_service.dart';
import '../../utils/library_selection.dart';
import '../../widgets/empty_state_view.dart';
import '../../widgets/library/library_root_picker.dart';
import '../../widgets/tv/tv_error_panel.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/tv/tv_continue_section.dart';
import '../../widgets/tv/tv_keyboard_handler.dart';
import '../../widgets/tv/tv_home_layout.dart';
import '../../widgets/tv/tv_recommend_rail.dart';
import '../../widgets/tv/tv_sidebar_nav.dart';
import '../library_screen.dart';

class TvHomeShell extends ConsumerStatefulWidget {
  const TvHomeShell({
    super.key,
    required this.libraries,
    this.librariesLoading = false,
    this.librariesError,
    required this.resume,
    required this.emby,
    required this.onRefresh,
    this.onRetryLibraries,
  });

  final List<EmbyLibrary> libraries;
  final bool librariesLoading;
  final Object? librariesError;
  final List<EmbyMediaItem> resume;
  final EmbyService emby;
  final Future<void> Function() onRefresh;
  final VoidCallback? onRetryLibraries;

  @override
  ConsumerState<TvHomeShell> createState() => _TvHomeShellState();
}

class _TvHomeShellState extends ConsumerState<TvHomeShell> {
  TvNavItem _nav = TvNavItem.home;

  final _browseTabKeys = <TvNavItem, GlobalKey<_TvBrowseTabPaneState>>{
    TvNavItem.movies: GlobalKey<_TvBrowseTabPaneState>(),
    TvNavItem.series: GlobalKey<_TvBrowseTabPaneState>(),
    TvNavItem.library: GlobalKey<_TvBrowseTabPaneState>(),
  };

  void _selectNav(TvNavItem item) => setState(() => _nav = item);

  void _onBack() {
    if (_nav != TvNavItem.home) {
      final popped = _browseTabKeys[_nav]?.currentState?.popStack() ?? false;
      if (popped) return;
      setState(() => _nav = TvNavItem.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TvSidebarNav(
              selected: _nav,
              onHome: () => _selectNav(TvNavItem.home),
              onMovies: () => _selectNav(TvNavItem.movies),
              onSeries: () => _selectNav(TvNavItem.series),
              onLibrary: () => _selectNav(TvNavItem.library),
              onSearch: () => context.push('/search'),
              onSettings: () => context.push('/settings'),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showContent = constraints.maxWidth >= 200;
                  return Visibility(
                    visible: showContent,
                    maintainState: true,
                    maintainAnimation: true,
                    child: TvKeyboardHandler(
                      child: IndexedStack(
                        index: _nav.index,
                        sizing: StackFit.expand,
                        children: [
                          _TvShellKeepAliveTab(
                            child: _TvHomeTabPane(
                              resume: widget.resume,
                              emby: widget.emby,
                            ),
                          ),
                          _TvShellKeepAliveTab(
                            child: _TvBrowseTabPane(
                              key: _browseTabKeys[TvNavItem.movies],
                              nav: TvNavItem.movies,
                              libraries: widget.libraries,
                              librariesLoading: widget.librariesLoading,
                              librariesError: widget.librariesError,
                              onRetryLibraries: widget.onRetryLibraries,
                            ),
                          ),
                          _TvShellKeepAliveTab(
                            child: _TvBrowseTabPane(
                              key: _browseTabKeys[TvNavItem.series],
                              nav: TvNavItem.series,
                              libraries: widget.libraries,
                              librariesLoading: widget.librariesLoading,
                              librariesError: widget.librariesError,
                              onRetryLibraries: widget.onRetryLibraries,
                            ),
                          ),
                          _TvShellKeepAliveTab(
                            child: _TvBrowseTabPane(
                              key: _browseTabKeys[TvNavItem.library],
                              nav: TvNavItem.library,
                              libraries: widget.libraries,
                              librariesLoading: widget.librariesLoading,
                              librariesError: widget.librariesError,
                              onRetryLibraries: widget.onRetryLibraries,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps off-screen TV tabs alive (scroll position, paginated cache, images).
class _TvShellKeepAliveTab extends StatefulWidget {
  const _TvShellKeepAliveTab({required this.child});

  final Widget child;

  @override
  State<_TvShellKeepAliveTab> createState() => _TvShellKeepAliveTabState();
}

class _TvShellKeepAliveTabState extends State<_TvShellKeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _TvHomeTabPane extends StatelessWidget {
  const _TvHomeTabPane({
    required this.resume,
    required this.emby,
  });

  final List<EmbyMediaItem> resume;
  final EmbyService emby;

  @override
  Widget build(BuildContext context) {
    final viewportW = TvHomeLayout.viewportWidthOf(context);
    final gap = TvHomeLayout.sectionGapFor(viewportW);

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          TvHomeLayout.contentPaddingLeft(context),
          TvHomeLayout.contentPaddingTop(context),
          TvHomeLayout.contentPaddingRight(context),
          TvHomeLayout.contentPaddingBottom(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TvContinueSection(
              items: resume,
              emby: emby,
              autofocusHero: true,
              onViewAll: () => context.push('/recent-play'),
            ),
            SizedBox(height: gap),
            Expanded(child: TvRecommendRail(emby: emby)),
          ],
        ),
      ),
    );
  }
}

/// Self-contained movies / series / library browse tab — isolates rebuild scope.
class _TvBrowseTabPane extends StatefulWidget {
  const _TvBrowseTabPane({
    super.key,
    required this.nav,
    required this.libraries,
    this.librariesLoading = false,
    this.librariesError,
    this.onRetryLibraries,
  });

  final TvNavItem nav;
  final List<EmbyLibrary> libraries;
  final bool librariesLoading;
  final Object? librariesError;
  final VoidCallback? onRetryLibraries;

  @override
  State<_TvBrowseTabPane> createState() => _TvBrowseTabPaneState();
}

class _TvBrowseTabPaneState extends State<_TvBrowseTabPane> {
  String? _selectedMovieLibraryId;
  String? _selectedSeriesLibraryId;
  String? _selectedAllLibraryId;
  final _browseStack = <({String id, String name})>[];

  bool popStack() {
    if (_browseStack.isEmpty) return false;
    setState(() => _browseStack.removeLast());
    return true;
  }

  String? _libraryTypes() {
    switch (widget.nav) {
      case TvNavItem.movies:
        return 'Movie';
      case TvNavItem.series:
        return 'Series';
      case TvNavItem.library:
      case TvNavItem.home:
        return null;
    }
  }

  void _onLibrarySelected(String libraryId) {
    setState(() {
      switch (widget.nav) {
        case TvNavItem.movies:
          _selectedMovieLibraryId = libraryId;
          break;
        case TvNavItem.series:
          _selectedSeriesLibraryId = libraryId;
          break;
        case TvNavItem.library:
        case TvNavItem.home:
          _selectedAllLibraryId = libraryId;
          break;
      }
      _browseStack.clear();
    });
  }

  LibraryScope _libraryScope() {
    switch (widget.nav) {
      case TvNavItem.movies:
        return buildLibraryScope(
          libraries: widget.libraries,
          selectedLibraryId: _selectedMovieLibraryId,
          allLabel: '全部电影',
          collectionTypes: const {'movies'},
        );
      case TvNavItem.series:
        return buildLibraryScope(
          libraries: widget.libraries,
          selectedLibraryId: _selectedSeriesLibraryId,
          allLabel: '全部电视剧',
          collectionTypes: const {'tvshows'},
        );
      case TvNavItem.library:
      case TvNavItem.home:
        return buildLibraryScope(
          libraries: widget.libraries,
          selectedLibraryId: _selectedAllLibraryId,
          allLabel: '全部媒体库',
          includeAll: true,
        );
    }
  }

  void _onBrowseIntoFolder(EmbyMediaItem folder) {
    setState(() => _browseStack.add((id: folder.id, name: folder.name)));
  }

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(
      TvHomeLayout.contentPaddingLeft(context),
      TvHomeLayout.contentPaddingTop(context),
      TvHomeLayout.contentPaddingRight(context),
      TvHomeLayout.contentPaddingBottom(context),
    );

    if (widget.librariesLoading) {
      return Padding(
        padding: padding,
        child: const Center(child: LoadingIndicator(message: '加载媒体库…')),
      );
    }
    if (widget.librariesError != null) {
      return Padding(
        padding: padding,
        child: TvErrorPanel(
          error: widget.librariesError,
          onRetry: widget.onRetryLibraries,
        ),
      );
    }
    if (widget.libraries.isEmpty) {
      return Padding(
        padding: padding,
        child: EmptyStateView(
          icon: Icons.video_library_outlined,
          title: '没有可用媒体库',
          subtitle: '请检查服务器配置或稍后重试',
          actionLabel: '重试',
          autofocusAction: true,
          onAction: widget.onRetryLibraries,
        ),
      );
    }

    final scope = _libraryScope();
    final browseParentId = _browseStack.isEmpty
        ? (scope.selectedParentId ?? '')
        : _browseStack.last.id;
    final types = _libraryTypes();

    return Padding(
      padding: padding,
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LibraryRootPicker(
              libraries: scope.pickerLibraries,
              selectedId: scope.selectedId,
              onSelected: _onLibrarySelected,
              tv: true,
            ),
            Expanded(
              child: LibraryBrowseBody(
                key: ValueKey(
                    'tv-browse-${widget.nav}-$browseParentId-$types-${scope.selectedId}'),
                parentId: browseParentId,
                includeItemTypes: types,
                allItems: _browseStack.isEmpty ? scope.allItems : null,
                onBrowseIntoFolder: _onBrowseIntoFolder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
