import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_client/core/storage/local_storage.dart';
import 'package:media_client/models/emby/emby_library.dart';
import 'package:media_client/models/emby/emby_media_item.dart';
import 'package:media_client/providers/emby_provider.dart';
import 'package:media_client/providers/settings_provider.dart';
import 'package:media_client/widgets/library/media_browse_view.dart';

void main() {
  testWidgets('影视页按类型展示分类 chips 与卡片', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await LocalStorage.open();

    const libraries = [
      EmbyLibrary(id: 'l-guoman', name: '国漫', collectionType: 'tvshows'),
      EmbyLibrary(id: 'l-riban', name: '日番', collectionType: 'tvshows'),
      EmbyLibrary(id: 'l-movie', name: '动画电影', collectionType: 'movies'),
    ];
    const seriesItem = EmbyMediaItem(id: 's1', name: '仙逆', type: 'Series');
    const movieItem = EmbyMediaItem(id: 'm1', name: '深海', type: 'Movie');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          embyLibrariesProvider.overrideWith((ref) async => libraries),
          embyLibraryItemsProvider.overrideWith(
            (ref, arg) async => arg.includeItemTypes == 'Movie'
                ? const [movieItem]
                : const [seriesItem],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MediaBrowseView())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('剧集'), findsWidgets);
    expect(find.text('电影'), findsWidgets);
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
