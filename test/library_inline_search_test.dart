import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/models/emby/emby_library.dart';
import 'package:media_client/providers/emby_provider.dart';
import 'package:media_client/screens/library_screen.dart';
import 'package:media_client/utils/library_selection.dart';
import 'package:media_client/widgets/home/home_pc_search_header.dart';
import 'package:media_client/widgets/library/library_root_picker.dart';

EmbyLibraryListArg _query(String parentId, String? itemsQuery,
    {String? searchTerm}) {
  return libraryItemsQuery(parentId, itemsQuery, searchTerm: searchTerm);
}

void main() {
  const libraries = [
    EmbyLibrary(id: 'movies-a', name: '欧美电影', collectionType: 'movies'),
    EmbyLibrary(id: 'movies-b', name: '纪录片', collectionType: 'movies'),
    EmbyLibrary(id: 'series-a', name: '欧美剧', collectionType: 'tvshows'),
  ];

  test('buildLibraryScope defaults movies tab to first movie library', () {
    final scope = buildLibraryScope(
      libraries: libraries,
      selectedLibraryId: null,
      allLabel: '全部电影',
      collectionTypes: const {'movies'},
    );

    expect(scope.selectedId, 'movies-a');
    expect(scope.selectedParentId, 'movies-a');
    expect(scope.pickerLibraries.map((l) => l.name), [
      '欧美电影',
      '纪录片',
    ]);
    expect(scope.allItems, isNull);
  });

  test('buildLibraryScope keeps selected library inside its own tab only', () {
    final movieScope = buildLibraryScope(
      libraries: libraries,
      selectedLibraryId: 'movies-b',
      allLabel: '全部电影',
      collectionTypes: const {'movies'},
    );
    final seriesScope = buildLibraryScope(
      libraries: libraries,
      selectedLibraryId: 'movies-b',
      allLabel: '全部电视剧',
      collectionTypes: const {'tvshows'},
    );

    expect(movieScope.selectedId, 'movies-b');
    expect(movieScope.selectedParentId, 'movies-b');
    expect(seriesScope.selectedId, 'series-a');
    expect(seriesScope.selectedParentId, 'series-a');
    expect(seriesScope.pickerLibraries.map((i) => i.name), ['欧美剧']);
  });

  test('buildLibraryScope defaults library tab to all top-level libraries', () {
    final scope = buildLibraryScope(
      libraries: libraries,
      selectedLibraryId: null,
      allLabel: '全部媒体库',
      includeAll: true,
    );

    expect(scope.selectedId, LibraryScope.allId);
    expect(scope.selectedParentId, isNull);
    expect(scope.pickerLibraries.map((l) => l.name), [
      '全部媒体库',
      '欧美电影',
      '纪录片',
      '欧美剧',
    ]);
    expect(scope.allItems!.map((i) => (id: i.id, name: i.name, type: i.type)), [
      (id: 'movies-a', name: '欧美电影', type: 'CollectionFolder'),
      (id: 'movies-b', name: '纪录片', type: 'CollectionFolder'),
      (id: 'series-a', name: '欧美剧', type: 'CollectionFolder'),
    ]);
  });

  test('libraryItemsQuery carries search term for Emby item search', () {
    final arg = _query('movies-root', 'Movie', searchTerm: '盗梦');

    expect(arg.parentId, 'movies-root');
    expect(arg.includeItemTypes, 'Movie');
    expect(arg.recursive, isTrue);
    expect(arg.searchTerm, '盗梦');
  });

  test('libraryItemsQuery trims blank search term to null', () {
    final arg = _query('series-root', 'Series', searchTerm: '   ');

    expect(arg.searchTerm, isNull);
  });

  testWidgets('LibraryRootChipPicker keeps overflow categories in top drawer',
      (tester) async {
    String? selected;
    const libraries = [
      EmbyLibrary(id: 'movies-a', name: '欧美电影', collectionType: 'movies'),
      EmbyLibrary(id: 'movies-b', name: '纪录片', collectionType: 'movies'),
      EmbyLibrary(id: 'movies-c', name: '动画电影', collectionType: 'movies'),
      EmbyLibrary(id: 'movies-d', name: '华语电影', collectionType: 'movies'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: LibraryRootChipPicker(
                libraries: libraries,
                selectedId: 'movies-a',
                onSelected: (id) => selected = id,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('欧美电影'), findsOneWidget);
    expect(find.text('纪录片'), findsOneWidget);
    expect(find.text('华语电影'), findsNothing);
    expect(find.byTooltip('展开全部分类'), findsOneWidget);

    await tester.tap(find.byTooltip('展开全部分类'));
    await tester.pumpAndSettle();

    final sheetTop = tester.getTopLeft(find.text('选择分类')).dy;
    expect(sheetTop, lessThan(180));
    expect(find.text('华语电影'), findsOneWidget);

    await tester.tap(find.text('华语电影'));
    await tester.pumpAndSettle();

    expect(selected, 'movies-d');
    expect(find.text('华语电影'), findsNothing);
  });

  testWidgets('LibraryRootChipPicker swaps selected overflow category into row',
      (tester) async {
    const libraries = [
      EmbyLibrary(id: 'movies-a', name: '欧美电影', collectionType: 'movies'),
      EmbyLibrary(id: 'movies-b', name: '纪录片', collectionType: 'movies'),
      EmbyLibrary(id: 'movies-c', name: '动画电影', collectionType: 'movies'),
      EmbyLibrary(id: 'movies-d', name: '华语电影', collectionType: 'movies'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: LibraryRootChipPicker(
                libraries: libraries,
                selectedId: 'movies-d',
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('欧美电影'), findsOneWidget);
    expect(find.text('纪录片'), findsNothing);
    expect(find.text('华语电影'), findsOneWidget);
    expect(find.byTooltip('展开全部分类'), findsOneWidget);
  });

  testWidgets('LibraryRootChipPicker underline follows selected text width',
      (tester) async {
    const libraries = [
      EmbyLibrary(id: 'short', name: '日剧', collectionType: 'tvshows'),
      EmbyLibrary(id: 'long', name: '电视剧-纪录片', collectionType: 'tvshows'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: LibraryRootChipPicker(
                libraries: libraries,
                selectedId: 'long',
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final textWidth = tester.getSize(find.text('电视剧-纪录片')).width;
    final underlineWidth = tester
        .getSize(find.byKey(const ValueKey('library-tab-underline-long')))
        .width;

    expect(underlineWidth, textWidth);
  });

  testWidgets('HomePcSearchHeader edits inline instead of acting as a button',
      (tester) async {
    final changes = <String>[];
    String? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePcSearchHeader(
            query: '',
            hintText: '搜索当前电影',
            onChanged: changes.add,
            onSubmitted: (value) => submitted = value,
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('搜索当前电影'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '星际');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(changes, contains('星际'));
    expect(submitted, '星际');
  });
}
