import 'package:flutter/foundation.dart';
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
import 'package:media_client/widgets/library/library_browse_recommend_card.dart';
import 'package:media_client/widgets/library/media_browse_view.dart';

const _libraries = [
  EmbyLibrary(id: 'l-tv', name: '电视剧', collectionType: 'tvshows'),
  EmbyLibrary(id: 'l-movie', name: '电影', collectionType: 'movies'),
];

class _FakeEmbyService extends EmbyService {
  _FakeEmbyService(super.settings, this.count);

  final int count;

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
    final items = [
      for (var i = 0; i < count; i++)
        EmbyMediaItem(
          id: 'item-$i',
          name: '剧集 $i',
          type: includeItemTypes == 'Movie' ? 'Movie' : 'Series',
        ),
    ];
    return (items: items, total: count);
  }
}

/// 注意：`debugDefaultTargetPlatformOverride` 必须在测试体结束前手动清空，
/// 否则 flutter_test 的 foundation 不变量检查会报错（tearDown 太晚）。
Future<void> _pumpBrowse(
  WidgetTester tester, {
  required Size size,
  required TargetPlatform platform,
  int count = 8,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  debugDefaultTargetPlatformOverride = platform;

  SharedPreferences.setMockInitialValues({});
  final storage = await LocalStorage.open();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
        embyLibrariesProvider.overrideWith((ref) async => _libraries),
        embyServiceProvider.overrideWith(
          (ref) => _FakeEmbyService(ref.watch(settingsServiceProvider), count),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: MediaBrowseView())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('桌面：页头与海报网格对齐同一内容列，计数可见', (tester) async {
    await _pumpBrowse(
      tester,
      size: const Size(1440, 900),
      platform: TargetPlatform.windows,
    );

    expect(find.text('影视'), findsOneWidget);
    expect(find.text('共 8 部'), findsOneWidget);
    expect(find.byType(LibraryBrowseRecommendCard), findsWidgets);

    final titleLeft = tester.getTopLeft(find.text('影视')).dx;
    final firstCardLeft =
        tester.getTopLeft(find.byType(LibraryBrowseRecommendCard).first).dx;
    // 页头与网格共用同一水平内边距 / 居中列：两者左边缘必须一致。
    expect((titleLeft - firstCardLeft).abs(), lessThan(0.5));

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('手机：chip 命中区 ≥48dp，标题不重复', (tester) async {
    await _pumpBrowse(
      tester,
      size: const Size(390, 844),
      platform: TargetPlatform.android,
    );

    // 手机端标题由 AppBar 提供，页内不再重复。
    expect(find.text('影视'), findsNothing);
    expect(find.text('共 8 部'), findsOneWidget);

    // 分类 chip：命中区由外层 GestureDetector 决定。
    final allChip = find.text('全部');
    expect(allChip, findsOneWidget);
    final chipHit = find
        .ancestor(of: allChip, matching: find.byType(GestureDetector))
        .first;
    expect(tester.getSize(chipHit).height, greaterThanOrEqualTo(48));

    // 类型分段：命中区由 InkWell 决定。
    final kindHit = find
        .ancestor(of: find.text('剧集').first, matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(kindHit).height, greaterThanOrEqualTo(48));

    // 排序控件在当前值上可见。
    expect(find.text('最近更新'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('窄屏 + 搜索展开不溢出', (tester) async {
    await _pumpBrowse(
      tester,
      size: const Size(360, 800),
      platform: TargetPlatform.android,
    );

    await tester.tap(find.byTooltip('搜索'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TextField), findsOneWidget);

    // 输入后防抖 300ms 才发请求，期间不应抛异常或清空页面。
    await tester.enterText(find.byType(TextField), '仙');
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });
}
