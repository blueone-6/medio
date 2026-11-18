import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_client/core/storage/local_storage.dart';
import 'package:media_client/models/emby/emby_library.dart';
import 'package:media_client/models/emby/emby_media_item.dart';
import 'package:media_client/providers/emby_provider.dart';
import 'package:media_client/providers/settings_provider.dart';
import 'package:media_client/services/emby_service.dart';
import 'package:media_client/widgets/library/media_browse_view.dart';

const _seriesItem = EmbyMediaItem(id: 's1', name: '仙逆', type: 'Series');
const _movieItem = EmbyMediaItem(id: 'm1', name: '深海', type: 'Movie');

/// 影视页现在走分页接口，测试注入一页结果即可。
class _FakeEmbyService extends EmbyService {
  _FakeEmbyService(super.settings);

  @override
  Future<EmbyItemsPage> getItemsPage({
    String? parentId,
    int startIndex = 0,
    int limit = 50,
    String? includeItemTypes,
    bool recursive = false,
    String? sortBy,
    String? sortOrder,
    String? years,
    String? filters,
    String? searchTerm,
    bool enableUserData = false,
  }) async {
    final items =
        includeItemTypes == 'Movie' ? const [_movieItem] : const [_seriesItem];
    return (items: items, total: items.length);
  }
}

void main() {
  testWidgets('影视页按类型展示分类 chips 与卡片', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await LocalStorage.open();

    const libraries = [
      EmbyLibrary(id: 'l-guoman', name: '国漫', collectionType: 'tvshows'),
      EmbyLibrary(id: 'l-riban', name: '日番', collectionType: 'tvshows'),
      EmbyLibrary(id: 'l-movie', name: '动画电影', collectionType: 'movies'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          embyLibrariesProvider.overrideWith((ref) async => libraries),
          embyServiceProvider.overrideWith(
            (ref) => _FakeEmbyService(ref.watch(settingsServiceProvider)),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MediaBrowseView())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 类型分段 + 计数行。
    expect(find.text('剧集'), findsWidgets);
    expect(find.text('电影'), findsWidgets);
    expect(find.textContaining('共 1 部'), findsOneWidget);

    // 分类 chips 只包含当前类型的库。
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('国漫'), findsOneWidget);
    expect(find.text('日番'), findsOneWidget);
    expect(find.text('动画电影'), findsNothing);
    expect(find.text('仙逆'), findsOneWidget);

    await tester.tap(find.text('电影').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('动画电影'), findsOneWidget);
    expect(find.text('国漫'), findsNothing);
    expect(find.text('深海'), findsOneWidget);
  });
}
