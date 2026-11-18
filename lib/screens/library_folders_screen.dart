import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/platform_layout.dart';
import '../core/theme/app_spacing.dart';
import '../models/emby/emby_library.dart';
import '../providers/emby_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/library_selection.dart';
import '../utils/user_facing_error.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/error_view.dart';
import '../widgets/library/library_root_picker.dart';
import 'library_screen.dart';

/// 全屏「媒体库」文件夹视图（Emby 目录映射）。
///
/// 影视页（卡片 + 分类筛选）之外保留的兜底入口：手机端从「更多 → 媒体库」进入，
/// 桌面/TV 由侧栏「媒体库」直接内嵌同一套 UI。
class LibraryFoldersScreen extends ConsumerStatefulWidget {
  const LibraryFoldersScreen({super.key});

  @override
  ConsumerState<LibraryFoldersScreen> createState() =>
      _LibraryFoldersScreenState();
}

class _LibraryFoldersScreenState extends ConsumerState<LibraryFoldersScreen> {
  static const _kMobileLibraryKey = 'home.mobileLibraryId';

  String? _libraryId;
  final List<({String id, String name})> _stack = [];

  @override
  void initState() {
    super.initState();
    try {
      _libraryId = ref.read(localStorageProvider).getString(_kMobileLibraryKey);
    } catch (_) {
      // 存储不可用时使用第一个库
    }
  }

  void _onLibrarySelected(String libraryId) {
    setState(() {
      _libraryId = libraryId;
      _stack.clear();
    });
    try {
      ref.read(localStorageProvider).setString(_kMobileLibraryKey, libraryId);
    } catch (_) {
      // 忽略
    }
  }

  @override
  Widget build(BuildContext context) {
    final librariesAsync = ref.watch(embyLibrariesProvider);
    final libraries = librariesAsync.value ?? const <EmbyLibrary>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体库'),
        leading: _stack.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回上一级',
                onPressed: () => setState(() => _stack.removeLast()),
              )
            : null,
      ),
      body: SafeArea(
        top: false,
        child: librariesAsync.hasError && libraries.isEmpty
            ? ErrorView.forHomeSection(
                error: librariesAsync.error!,
                section: HomeLoadSection.libraries,
                onRetry: () => ref.invalidate(embyLibrariesProvider),
                onOpenSettings: () => Navigator.of(context).maybePop(),
              )
            : libraries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(kMobileHorizontalPadding),
                    child: EmptyStateView(
                      icon: Icons.video_library_outlined,
                      title: '没有可用媒体库',
                      subtitle: '请检查服务器配置或稍后重试',
                      actionLabel: '重试',
                      onAction: () => ref.invalidate(embyLibrariesProvider),
                    ),
                  )
                : _buildBody(libraries),
      ),
    );
  }

  Widget _buildBody(List<EmbyLibrary> libraries) {
    final rootId = normalizeSelectedLibraryId(libraries, _libraryId)!;
    final browseParentId = _stack.isEmpty ? rootId : _stack.last.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kMobileHorizontalPadding,
            8,
            kMobileHorizontalPadding,
            0,
          ),
          child: LibraryRootPicker(
            libraries: libraries,
            selectedId: rootId,
            onSelected: _onLibrarySelected,
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          ),
        ),
        Expanded(
          child: LibraryBrowseBody(
            key: ValueKey('folders-$browseParentId'),
            parentId: browseParentId,
            onBrowseIntoFolder: (folder) =>
                setState(() => _stack.add((id: folder.id, name: folder.name))),
          ),
        ),
      ],
    );
  }
}
