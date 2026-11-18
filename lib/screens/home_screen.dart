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
import '../widgets/library/media_browse_view.dart';
import '../widgets/loading_indicator.dart';
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
  String? _desktopAllLibraryId;
  final List<({String id, String name})> _libraryBrowseStack = [];
  Timer? _autoRefreshTimer;
  Timer? _autoRetryTimer;
  int _autoRetryAttempt = 0;
  static const _maxAutoRetryAttempts = 8;
  bool _appStartupPerfFinished = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _autoRefreshTimer =
        Timer.periodic(const Duration(minutes: 10), (_) => _onAutoRefresh());
    // Auto-retry library loading when the server is temporarily unreachable
    // (e.g. Emby server still starting up). Exponential backoff: 5s, 10s, 15s,
    // 30s, 30s, ... up to 8 attempts. Cancels automatically on success or when
    // the user manually retries.
    ref.listenManual(embyLibrariesProvider, (prev, next) {
      if (next.hasError && !next.isLoading) {
        _scheduleAutoRetry();
      } else if (next.hasValue) {
        _cancelAutoRetry();
      }
    });
    _restoreLibrarySelection();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _finishAppStartupPerf());
  }

  void _scheduleAutoRetry() {
    if (_autoRetryAttempt >= _maxAutoRetryAttempts) return;
    _autoRetryTimer?.cancel();
    _autoRetryAttempt++;
    final delaySeconds = (_autoRetryAttempt <= 3)
        ? 5 * _autoRetryAttempt // 5s, 10s, 15s
        : 30; // 30s thereafter
    _autoRetryTimer = Timer(
      Duration(seconds: delaySeconds),
      () {
        if (!mounted) return;
        ref.invalidate(embyLibrariesProvider);
        ref.invalidate(embyResumeProvider);
      },
    );
  }

  void _cancelAutoRetry() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
    _autoRetryAttempt = 0;
  }

  void _finishAppStartupPerf() {
    if (_appStartupPerfFinished) return;
    _appStartupPerfFinished = true;
    PerfTracer.finishAppStartupAtHome();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _autoRetryTimer?.cancel();
    super.dispose();
  }

  void _onAutoRefresh() {
    ref.invalidate(embyResumeProvider);
    ref.invalidate(embyLatestProvider);
    ref.invalidate(homeRecommendationProvider);
  }

  Future<void> _onPullRefresh() async {
    _cancelAutoRetry();
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
      } else if (_desktopNav == HomePcNavItem.titles && libs.isNotEmpty) {
        // 影视页自行管理分类/排序，这里只需让列表重新拉取
        ref.invalidate(embyLibraryItemsProvider);
      } else if (libs.isNotEmpty) {
        final scope = _desktopLibraryScope(libs);
        if (scope.selectedParentId != null || _libraryBrowseStack.isNotEmpty) {
          final browseId = _libraryBrowseStack.isEmpty
              ? scope.selectedParentId!
              : _libraryBrowseStack.last.id;
          final query = libraryItemsQuery(browseId, null);
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

    // 首页和设置页不依赖 libraries 数据：即使媒体库加载失败也直接渲染，
    // 确保用户始终能进入设置修改服务器配置，不会被困在错误界面。
    if (_desktopNav == HomePcNavItem.home ||
        _desktopNav == HomePcNavItem.settings) {
      final resume = resumeAsync.value ?? const <EmbyMediaItem>[];
      return _buildDesktopMainPane(
        context,
        libs ?? const <EmbyLibrary>[],
        emby,
        resume,
        resumeAsync,
      );
    }

    if (libraries.hasError && libs == null) {
      return ErrorView.forHomeSection(
        error: libraries.error!,
        section: HomeLoadSection.libraries,
        onRetry: () => ref.invalidate(embyLibrariesProvider),
        onOpenSettings: _openDesktopSettings,
      );
    }
    if (libraries.isLoading && libs == null) {
      return const LoadingIndicator.homeFeed();
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
    bool resumeLoading = false,
  }) {
    return [
      const SliverToBoxAdapter(child: HomeSearchBar()),
      SliverToBoxAdapter(
        child: ContinueWatchingSection(
          items: resumeItems,
          emby: emby,
          compact: compactContinue,
          onViewAll: () => context.push('/recent-play'),
          isLoading: resumeLoading,
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
      BuildContext context, EmbyService emby, List<EmbyMediaItem> resume,
      {bool isLoading = false}) {
    return RefreshIndicator(
      onRefresh: _onPullRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: _homeContentSlivers(
            context: context,
            emby: emby,
            resumeItems: resume,
            resumeLoading: isLoading),
      ),
    );
  }

  void _onDesktopLibrarySelected(String libraryId) {
    setState(() {
      if (_desktopNav == HomePcNavItem.library) {
        _desktopAllLibraryId = libraryId;
      }
      _libraryBrowseStack.clear();
    });
    if (_desktopNav == HomePcNavItem.library) {
      _persistLibraryId(_kDesktopAllLibraryKey, libraryId);
    }
  }

  // 记住上次选中的媒体库：分类库拆分后（国漫/日番/欧美剧…）重启回到第一个库体验很差
  static const _kDesktopAllLibraryKey = 'home.desktopAllLibraryId';

  void _restoreLibrarySelection() {
    try {
      final ls = ref.read(localStorageProvider);
      _desktopAllLibraryId = ls.getString(_kDesktopAllLibraryKey);
    } catch (_) {
      // 存储不可用时忽略，回退到默认库
    }
  }

  void _persistLibraryId(String key, String libraryId) {
    try {
      ref.read(localStorageProvider).setString(key, libraryId);
    } catch (_) {
      // 忽略写失败
    }
  }

  Widget _buildAndroidMediaTab(BuildContext context) {
    return const MediaBrowseView();
  }

  void _onLibraryBack() {
    setState(() {
      if (_libraryBrowseStack.isNotEmpty) {
        _libraryBrowseStack.removeLast();
      } else if (_desktopNav == HomePcNavItem.library) {
        _desktopNav = HomePcNavItem.home;
      }
    });
  }

  void _selectDesktopNav(HomePcNavItem nav) {
    setState(() {
      _desktopNav = nav;
      _libraryBrowseStack.clear();
    });
  }

  LibraryScope _desktopLibraryScope(List<EmbyLibrary> libraries) {
    switch (_desktopNav) {
      case HomePcNavItem.library:
        return buildLibraryScope(
          libraries: libraries,
          selectedLibraryId: _desktopAllLibraryId,
          allLabel: '全部媒体库',
          includeAll: true,
        );
      case HomePcNavItem.home:
      case HomePcNavItem.titles:
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
      case HomePcNavItem.titles:
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            HomeLayout.horizontalMargin,
            HomeLayout.pcSectionGap,
            HomeLayout.horizontalMargin,
            0,
          ),
          child: _buildDesktopFillPane(
            child: const MediaBrowseView(),
          ),
        );
      case HomePcNavItem.library:
        final scope = _desktopLibraryScope(libraries);
        final browseParentId = _libraryBrowseStack.isEmpty
            ? (scope.selectedParentId ?? '')
            : _libraryBrowseStack.last.id;
        return _buildDesktopBrowsePane(
          scope: scope,
          browseParentId: browseParentId,
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

    final showLibraryBack = _libraryBrowseStack.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: HomeLayout.pcContentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                HomeLayout.horizontalMargin,
                12,
                HomeLayout.horizontalMargin,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showLibraryBack)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _LibraryBackButton(onPressed: _onLibraryBack),
                    ),
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
            allItems: _libraryBrowseStack.isEmpty ? scope.allItems : null,
            onBrowseIntoFolder: (folder) {
              setState(() {
                _libraryBrowseStack.add((id: folder.id, name: folder.name));
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
    final resume = resumeAsync.value;
    final resumeError = resumeAsync.hasError ? resumeAsync.error : null;
    final resumeLoading = resume == null && resumeAsync.isLoading;

    // 始终使用 TvHomeShell（含侧边栏设置入口），不再用 TvScreenShell 替换
    // 整个屏幕。resume 加载失败时在首页 tab 内展示错误 + 去设置按钮，
    // 用户仍可通过侧边栏进入设置修改服务器配置。
    return TvHomeShell(
      libraries: libraries.value ?? const [],
      librariesLoading: libraries.isLoading,
      librariesError: libraries.hasError ? libraries.error : null,
      resume: resume ?? const [],
      resumeError: resumeError,
      resumeLoading: resumeLoading,
      emby: emby,
      onRefresh: _onPullRefresh,
      onRetryLibraries: () => ref.invalidate(embyLibrariesProvider),
      onRetryResume: () => ref.invalidate(embyResumeProvider),
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
      // 首页不依赖 libraries，直接渲染以避免骨架屏跳变。
      final libs = libraries.value;
      final resume = resumeAsync.value;

      // 不再用全屏错误替换整个 Shell：保留底部导航栏，让用户始终能
      // 切换到「更多」抽屉进入设置。媒体库加载失败时在 libraryTab 内
      // 展示错误，首页仍可正常使用（续播内容或续播错误）。
      return HomeAndroidShell(
        hideHomeAppBar: true,
        homeTab: resumeAsync.hasError && resume == null
            ? ErrorView.forHomeSection(
                error: resumeAsync.error!,
                section: HomeLoadSection.resume,
                onRetry: () => ref.invalidate(embyResumeProvider),
                onOpenSettings: () => context.push('/settings/servers'),
              )
            : _buildMobileHomeTab(
                context,
                emby,
                resume ?? const <EmbyMediaItem>[],
                isLoading: resume == null && resumeAsync.isLoading,
              ),
        titlesTab: libraries.hasError && libs == null
            ? ErrorView.forHomeSection(
                error: libraries.error!,
                section: HomeLoadSection.libraries,
                onRetry: () => ref.invalidate(embyLibrariesProvider),
                onOpenSettings: () => context.push('/settings/servers'),
              )
            : _buildAndroidMediaTab(context),
      );
    }

    return AppShortcuts(
      onSearch: () => context.push('/search'),
      onSettings: () => _selectDesktopNav(HomePcNavItem.settings),
      onRefresh: _onPullRefresh,
      child: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomePcSidebar(
              selected: _desktopNav,
              onHome: () => _selectDesktopNav(HomePcNavItem.home),
              onTitles: () => _selectDesktopNav(HomePcNavItem.titles),
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
