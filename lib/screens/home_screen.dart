import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/platform_layout.dart';
import '../core/logging/perf.dart';
import '../core/shortcuts/app_shortcuts.dart';
import '../core/theme/app_spacing.dart';
import '../models/emby/emby_library.dart';
import '../models/emby/emby_media_item.dart';
import '../providers/emby_provider.dart';
import '../providers/home_recommendation_provider.dart';
import '../providers/settings_provider.dart';
import '../services/emby_service.dart';
import '../utils/library_selection.dart';
import '../utils/user_facing_error.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/error_view.dart';
import '../widgets/library/library_root_picker.dart';
import '../widgets/home/continue_watching_pc_section.dart';
import '../widgets/home/continue_watching_section.dart';
import '../widgets/home/home_layout.dart';
import '../widgets/home/home_pc_search_header.dart';
import '../widgets/home/home_pc_sidebar.dart';
import '../widgets/home/home_search_bar.dart';
import '../widgets/home/recommendation_section.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/tv/tv_error_panel.dart';
import '../widgets/tv/tv_keyboard_handler.dart';
import 'home_android_shell.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'tv/tv_home_shell.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  HomePcNavItem _desktopNav = HomePcNavItem.home;
  String? _mobileLibraryId;
  String? _desktopMovieLibraryId;
  String? _desktopSeriesLibraryId;
  String? _desktopAllLibraryId;
  final List<({String id, String name})> _libraryBrowseStack = [];
  Timer? _autoRefreshTimer;
  Timer? _desktopSearchDebounce;
  late final FocusNode _desktopSearchFocusNode;
  String _desktopSearchInput = '';
  String _desktopSearchTerm = '';
  bool _appStartupPerfFinished = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _desktopSearchFocusNode = FocusNode();
    _autoRefreshTimer =
        Timer.periodic(const Duration(minutes: 10), (_) => _onAutoRefresh());
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _finishAppStartupPerf());
  }

  void _finishAppStartupPerf() {
    if (_appStartupPerfFinished) return;
    _appStartupPerfFinished = true;
    PerfTracer.finishAppStartupAtHome();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _desktopSearchDebounce?.cancel();
    _desktopSearchFocusNode.dispose();
    super.dispose();
  }

  void _onAutoRefresh() {
    ref.invalidate(embyResumeProvider);
    ref.invalidate(embyLatestProvider);
    ref.invalidate(homeRecommendationProvider);
  }

  Future<void> _onPullRefresh() async {
    if (_isRefreshing) return;
    if (mounted) setState(() => _isRefreshing = true);
    try {
      ref.invalidate(embyLibrariesProvider);
      ref.invalidate(embyResumeProvider);
      ref.invalidate(embyLatestProvider);
      ref.invalidate(homeRecommendationProvider);
      ref.invalidate(embyLibraryCategoryCoverProvider);
      ref.invalidate(embyItemProvider);
      ref.invalidate(embySeasonsProvider);
      ref.invalidate(embyEpisodesProvider);
      ref.invalidate(embyNextUpForSeriesProvider);
      ref.invalidate(embyItemPeopleProvider);
      ref.invalidate(embySimilarItemsProvider);
      final libs = await ref.read(embyLibrariesProvider.future);
      if (_desktopNav == HomePcNavItem.home) {
        await Future.wait([
          ref.read(embyResumeProvider.future),
          ref.read(homeRecommendationProvider.future),
        ]);
      } else if (libs.isNotEmpty) {
        final scope = _desktopLibraryScope(libs);
        if (scope.selectedParentId != null || _libraryBrowseStack.isNotEmpty) {
          final browseId = _libraryBrowseStack.isEmpty
              ? scope.selectedParentId!
              : _libraryBrowseStack.last.id;
          final types = _desktopLibraryTypes();
          final query = libraryItemsQuery(
            browseId,
            types,
            searchTerm: _desktopSearchTerm,
          );
          ref.invalidate(embyLibraryItemsProvider(query));
          await ref.read(embyLibraryItemsProvider(query).future);
        }
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _desktopNav == HomePcNavItem.home ? '首页内容已更新' : '媒体库已更新',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final info = userFacingErrorInfo(e);
      final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(info.message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: info.suggestsSettings
              ? SnackBarAction(
                  label: '去设置',
                  onPressed: _openDesktopSettings,
                )
              : SnackBarAction(
                  label: '重试',
                  onPressed: () => unawaited(_onPullRefresh()),
                ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _openDesktopSettings() => _selectDesktopNav(HomePcNavItem.settings);

  Widget _buildDesktopMainArea({
    required BuildContext context,
    required AsyncValue<List<EmbyLibrary>> libraries,
    required AsyncValue<List<EmbyMediaItem>> resumeAsync,
    required EmbyService emby,
  }) {
    final libs = libraries.value;
    if (libraries.hasError && libs == null) {
      return ErrorView.forHomeSection(
        error: libraries.error!,
        section: HomeLoadSection.libraries,
        onRetry: () => ref.invalidate(embyLibrariesProvider),
        onOpenSettings: _openDesktopSettings,
      );
    }
    if (libraries.isLoading && libs == null) {
      // 首页和设置页不依赖 libraries，直接渲染以避免骨架屏跳变。
      final resume = resumeAsync.value ?? const <EmbyMediaItem>[];
      switch (_desktopNav) {
        case HomePcNavItem.home:
          return _buildDesktopHomeMain(context, emby, resume, resumeAsync);
        case HomePcNavItem.settings:
          return _buildDesktopSettingsPane();
        case HomePcNavItem.movies:
        case HomePcNavItem.series:
        case HomePcNavItem.library:
          return const LoadingIndicator.homeFeed();
      }
    }

    final resume = resumeAsync.value ?? const <EmbyMediaItem>[];
    return _buildDesktopMainPane(
      context,
      libs ?? const <EmbyLibrary>[],
      emby,
      resume,
      resumeAsync,
    );
  }

  List<Widget> _homeContentSlivers({
    required BuildContext context,
    required EmbyService emby,
    required List<EmbyMediaItem> resumeItems,
    bool compactContinue = false,
    bool horizontalRecommend = false,
    int? recommendColumns,
  }) {
    return [
      const SliverToBoxAdapter(child: HomeSearchBar()),
      SliverToBoxAdapter(
        child: ContinueWatchingSection(
          items: resumeItems,
          emby: emby,
          compact: compactContinue,
          onViewAll: () => context.push('/recent-play'),
        ),
      ),
      const SliverToBoxAdapter(
          child: SizedBox(height: HomeLayout.sectionHeaderGap)),
      SliverToBoxAdapter(
        child: RecommendationSection(
          emby: emby,
          horizontal: horizontalRecommend,
          crossAxisCount: recommendColumns,
        ),
      ),
      const SliverPadding(padding: EdgeInsets.only(bottom: AppSpacing.xxxl)),
    ];
  }

  Widget _buildMobileHomeTab(
      BuildContext context, EmbyService emby, List<EmbyMediaItem> resume) {
    return RefreshIndicator(
      onRefresh: _onPullRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: _homeContentSlivers(
            context: context, emby: emby, resumeItems: resume),
      ),
    );
  }

  void _onMobileLibrarySelected(String libraryId) {
    setState(() {
      _mobileLibraryId = libraryId;
      _libraryBrowseStack.clear();
    });
  }

  void _onDesktopLibrarySelected(String libraryId) {
    setState(() {
      switch (_desktopNav) {
        case HomePcNavItem.movies:
          _desktopMovieLibraryId = libraryId;
          break;
        case HomePcNavItem.series:
          _desktopSeriesLibraryId = libraryId;
          break;
        case HomePcNavItem.library:
          _desktopAllLibraryId = libraryId;
          break;
        case HomePcNavItem.home:
        case HomePcNavItem.settings:
          break;
      }
      _libraryBrowseStack.clear();
      _desktopSearchDebounce?.cancel();
      _desktopSearchInput = '';
      _desktopSearchTerm = '';
    });
  }

  Widget _buildAndroidLibraryTab(BuildContext context, List<EmbyLibrary> libs) {
    if (libs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(kMobileHorizontalPadding),
        child: EmptyStateView(
          icon: Icons.video_library_outlined,
          title: '没有可用媒体库',
          subtitle: '请检查服务器配置或稍后重试',
          actionLabel: '重试',
          onAction: () => ref.invalidate(embyLibrariesProvider),
        ),
      );
    }
    final rootId = normalizeSelectedLibraryId(libs, _mobileLibraryId)!;
    final browseParentId =
        _libraryBrowseStack.isEmpty ? rootId : _libraryBrowseStack.last.id;
    final showLibraryBack = _libraryBrowseStack.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              kMobileHorizontalPadding, 8, kMobileHorizontalPadding, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showLibraryBack)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _LibraryBackButton(
                    onPressed: () =>
                        setState(() => _libraryBrowseStack.removeLast()),
                  ),
                ),
              LibraryRootPicker(
                libraries: libs,
                selectedId: rootId,
                onSelected: _onMobileLibrarySelected,
                padding: EdgeInsets.only(
                  top: showLibraryBack ? 8 : 0,
                  bottom: AppSpacing.sm,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LibraryBrowseBody(
            parentId: browseParentId,
            onBrowseIntoFolder: (folder) {
              setState(() =>
                  _libraryBrowseStack.add((id: folder.id, name: folder.name)));
            },
          ),
        ),
      ],
    );
  }

  void _onLibraryBack() {
    setState(() {
      if (_libraryBrowseStack.isNotEmpty) {
        _libraryBrowseStack.removeLast();
        _desktopSearchDebounce?.cancel();
        _desktopSearchInput = '';
        _desktopSearchTerm = '';
      } else if (_desktopNav == HomePcNavItem.library) {
        _desktopNav = HomePcNavItem.home;
      }
    });
  }

  void _selectDesktopNav(HomePcNavItem nav) {
    setState(() {
      _desktopNav = nav;
      _libraryBrowseStack.clear();
      _desktopSearchDebounce?.cancel();
      _desktopSearchInput = '';
      _desktopSearchTerm = '';
    });
  }

  void _onDesktopSearchChanged(String value) {
    setState(() => _desktopSearchInput = value);
    _desktopSearchDebounce?.cancel();
    _desktopSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _desktopSearchTerm = _desktopSearchInput.trim());
    });
  }

  void _onDesktopSearchSubmitted(String value) {
    _desktopSearchDebounce?.cancel();
    setState(() {
      _desktopSearchInput = value;
      _desktopSearchTerm = value.trim();
    });
  }

  String? _desktopLibraryTypes() {
    switch (_desktopNav) {
      case HomePcNavItem.movies:
        return 'Movie';
      case HomePcNavItem.series:
        return 'Series';
      case HomePcNavItem.home:
      case HomePcNavItem.library:
      case HomePcNavItem.settings:
        return null;
    }
  }

  LibraryScope _desktopLibraryScope(List<EmbyLibrary> libraries) {
    switch (_desktopNav) {
      case HomePcNavItem.movies:
        return buildLibraryScope(
          libraries: libraries,
          selectedLibraryId: _desktopMovieLibraryId,
          allLabel: '全部电影',
          collectionTypes: const {'movies'},
        );
      case HomePcNavItem.series:
        return buildLibraryScope(
          libraries: libraries,
          selectedLibraryId: _desktopSeriesLibraryId,
          allLabel: '全部电视剧',
          collectionTypes: const {'tvshows'},
        );
      case HomePcNavItem.library:
        return buildLibraryScope(
          libraries: libraries,
          selectedLibraryId: _desktopAllLibraryId,
          allLabel: '全部媒体库',
          includeAll: true,
        );
      case HomePcNavItem.home:
      case HomePcNavItem.settings:
        return buildLibraryScope(
          libraries: libraries,
          selectedLibraryId: null,
          allLabel: '全部媒体库',
          includeAll: true,
        );
    }
  }

  Widget _buildDesktopSettingsPane() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HomeLayout.horizontalMargin,
        HomeLayout.pcSectionGap,
        HomeLayout.horizontalMargin,
        0,
      ),
      child: _buildDesktopFillPane(
        child: const SettingsScreen(embedded: true),
      ),
    );
  }

  Widget _buildDesktopFillPane({required Widget child}) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: HomeLayout.pcContentMaxWidth),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: child,
        ),
      ),
    );
  }

  Widget _buildDesktopMainPane(
    BuildContext context,
    List<EmbyLibrary> libraries,
    EmbyService emby,
    List<EmbyMediaItem> resume,
    AsyncValue<List<EmbyMediaItem>> resumeAsync,
  ) {
    switch (_desktopNav) {
      case HomePcNavItem.home:
        return _buildDesktopHomeMain(context, emby, resume, resumeAsync);
      case HomePcNavItem.settings:
        return _buildDesktopSettingsPane();
      case HomePcNavItem.movies:
      case HomePcNavItem.series:
      case HomePcNavItem.library:
        final scope = _desktopLibraryScope(libraries);
        final browseParentId = _libraryBrowseStack.isEmpty
            ? (scope.selectedParentId ?? '')
            : _libraryBrowseStack.last.id;
        return _buildDesktopBrowsePane(
          scope: scope,
          browseParentId: browseParentId,
          includeItemTypes: _desktopLibraryTypes(),
        );
    }
  }

  Widget _buildDesktopHomeMain(
    BuildContext context,
    EmbyService emby,
    List<EmbyMediaItem> resume,
    AsyncValue<List<EmbyMediaItem>> resumeAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomePcSearchHeader(onTap: () => context.push('/search')),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _onPullRefresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxWidth: HomeLayout.pcContentMaxWidth),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          HomeLayout.horizontalMargin,
                          HomeLayout.pcSectionGap,
                          HomeLayout.horizontalMargin,
                          HomeLayout.pcSectionGap,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ContinueWatchingPcSection(
                              items: resume,
                              emby: emby,
                              onViewAll: () => context.push('/recent-play'),
                              isLoading: resumeAsync.isLoading &&
                                  resumeAsync.value == null,
                              loadError: resumeAsync.hasError &&
                                      resumeAsync.value == null
                                  ? resumeAsync.error
                                  : null,
                              onRetry: () => ref.invalidate(embyResumeProvider),
                              onOpenSettings: _openDesktopSettings,
                            ),
                            const SizedBox(height: HomeLayout.pcSectionGap),
                            RecommendationSection(
                              emby: emby,
                              crossAxisCount: HomeLayout.pcRecommendColumns,
                              filterStyle: HomeRecommendFilterStyle.pill,
                              wrapInPadding: false,
                              usePcSectionTitle: true,
                              onOpenSettings: _openDesktopSettings,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopBrowsePane({
    required LibraryScope scope,
    required String browseParentId,
    required String? includeItemTypes,
  }) {
    final libraries = scope.pickerLibraries;
    if (libraries.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: HomeLayout.pcContentMaxWidth),
          child: Padding(
            padding: const EdgeInsets.all(HomeLayout.horizontalMargin),
            child: EmptyStateView(
              icon: Icons.video_library_outlined,
              title: '没有可用媒体库',
              subtitle: '请检查服务器配置或稍后重试',
              actionLabel: '重试',
              onAction: () => ref.invalidate(embyLibrariesProvider),
            ),
          ),
        ),
      );
    }

    final showSearch = _desktopNav == HomePcNavItem.movies ||
        _desktopNav == HomePcNavItem.series;
    final showLibraryBack = _desktopNav == HomePcNavItem.library;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSearch)
          HomePcSearchHeader(
            query: _desktopSearchInput,
            hintText: _desktopNav == HomePcNavItem.movies
                ? '搜索当前电影...'
                : '搜索当前电视剧...',
            onChanged: _onDesktopSearchChanged,
            onSubmitted: _onDesktopSearchSubmitted,
            focusNode: _desktopSearchFocusNode,
          ),
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: HomeLayout.pcContentMaxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                HomeLayout.horizontalMargin,
                showSearch ? AppSpacing.md : 12,
                HomeLayout.horizontalMargin,
                showSearch ? AppSpacing.xs : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showLibraryBack)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _LibraryBackButton(onPressed: _onLibraryBack),
                    ),
                  if (showSearch)
                    LibraryRootChipPicker(
                      libraries: libraries,
                      selectedId: scope.selectedId,
                      onSelected: _onDesktopLibrarySelected,
                      padding: const EdgeInsets.only(top: 0),
                    )
                  else
                    LibraryRootPicker(
                      libraries: libraries,
                      selectedId: scope.selectedId,
                      onSelected: _onDesktopLibrarySelected,
                      padding: EdgeInsets.only(top: showLibraryBack ? 8 : 0),
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: LibraryBrowseBody(
            parentId: browseParentId,
            includeItemTypes: includeItemTypes,
            searchTerm: _desktopSearchTerm,
            allItems: _libraryBrowseStack.isEmpty ? scope.allItems : null,
            onBrowseIntoFolder: (folder) {
              setState(() {
                _libraryBrowseStack.add((id: folder.id, name: folder.name));
                _desktopSearchDebounce?.cancel();
                _desktopSearchInput = '';
                _desktopSearchTerm = '';
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTvHome(
    AsyncValue<List<EmbyLibrary>> libraries,
    AsyncValue<List<EmbyMediaItem>> resumeAsync,
    EmbyService emby,
  ) {
    // Keep TvHomeShell mounted while resume refetches after leaving the player.
    // Replacing it with a loading scaffold drops TvRemoteActions and lets the
    // next system back finish the Activity.
    final resume = resumeAsync.value;
    if (resume == null && resumeAsync.isLoading) {
      return const Scaffold(
        body: Center(child: LoadingIndicator(message: '加载首页…')),
      );
    }
    if (resumeAsync.hasError && resume == null) {
      return TvScreenShell(
        title: '首页',
        body: TvErrorPanel(
          error: resumeAsync.error,
          onRetry: () => ref.invalidate(embyResumeProvider),
        ),
      );
    }

    // Home tab only needs resume; library browse can load in the background.
    return TvHomeShell(
      libraries: libraries.value ?? const [],
      librariesLoading: libraries.isLoading,
      librariesError: libraries.hasError ? libraries.error : null,
      resume: resume ?? const [],
      emby: emby,
      onRefresh: _onPullRefresh,
      onRetryLibraries: () => ref.invalidate(embyLibrariesProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final libraries = ref.watch(embyLibrariesProvider);
    final emby = ref.watch(embyServiceProvider);
    final resumeAsync = ref.watch(embyResumeProvider);

    if (context.isTvUi) {
      return _buildTvHome(libraries, resumeAsync, emby);
    }

    if (isAndroidMobileUi && !context.isTvUi) {
      return libraries.when(
        data: (libs) => resumeAsync.when(
          data: (resume) => HomeAndroidShell(
            hideHomeAppBar: true,
            homeTab: _buildMobileHomeTab(context, emby, resume),
            libraryTab: _buildAndroidLibraryTab(context, libs),
          ),
          loading: () => const HomeAndroidShell(
            hideHomeAppBar: true,
            homeTab: LoadingIndicator.homeFeed(),
            libraryTab: LoadingIndicator.posterGrid(homeRecommendStyle: true),
          ),
          error: (e, _) => HomeAndroidShell(
            hideHomeAppBar: true,
            homeTab: ErrorView.forHomeSection(
              error: e,
              section: HomeLoadSection.resume,
              onRetry: () => ref.invalidate(embyResumeProvider),
              onOpenSettings: () => context.push('/settings/servers'),
            ),
            libraryTab: _buildAndroidLibraryTab(context, libs),
          ),
        ),
        loading: () => const Scaffold(body: LoadingIndicator()),
        error: (e, _) => Scaffold(
          body: ErrorView.forHomeSection(
            error: e,
            section: HomeLoadSection.libraries,
            onRetry: () => ref.invalidate(embyLibrariesProvider),
            onOpenSettings: () => context.push('/settings/servers'),
          ),
        ),
      );
    }

    return AppShortcuts(
      onSearch: () {
        if (_desktopNav == HomePcNavItem.movies ||
            _desktopNav == HomePcNavItem.series) {
          _desktopSearchFocusNode.requestFocus();
          return;
        }
        context.push('/search');
      },
      onSettings: () => _selectDesktopNav(HomePcNavItem.settings),
      onRefresh: _onPullRefresh,
      child: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomePcSidebar(
              selected: _desktopNav,
              onHome: () => _selectDesktopNav(HomePcNavItem.home),
              onMovies: () => _selectDesktopNav(HomePcNavItem.movies),
              onSeries: () => _selectDesktopNav(HomePcNavItem.series),
              onLibrary: () => _selectDesktopNav(HomePcNavItem.library),
              onSettings: () => _selectDesktopNav(HomePcNavItem.settings),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildDesktopMainArea(
                      context: context,
                      libraries: libraries,
                      resumeAsync: resumeAsync,
                      emby: emby,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity: _isRefreshing ? 1 : 0,
                        child: const LinearProgressIndicator(minHeight: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryBackButton extends StatelessWidget {
  const _LibraryBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      tooltip: '返回',
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon:
          Icon(Icons.arrow_back_rounded, size: 22, color: cs.onSurfaceVariant),
    );
  }
}
