import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_client/core/api/api_exception.dart';
import 'package:media_client/core/storage/local_storage.dart';
import 'package:media_client/providers/emby_provider.dart';
import 'package:media_client/providers/settings_provider.dart';
import 'package:media_client/screens/home_screen.dart';

void main() {
  testWidgets('sidebar settings stays reachable when libraries fail',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    final storage = await LocalStorage.open();

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          embyLibrariesProvider.overrideWith(
            (ref) async =>
                throw ApiException('Access token is invalid or expired.',
                    statusCode: 401),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((s) => s != null)
        .toList();
    // ignore: avoid_print
    print('TEXTS: $texts');

    await tester.tap(find.text('媒体库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('媒体库加载失败'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('服务器配置'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('error view 去设置 button opens settings when libraries fail',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    final storage = await LocalStorage.open();

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          embyLibrariesProvider.overrideWith(
            (ref) async =>
                throw ApiException('Access token is invalid or expired.',
                    statusCode: 401),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('媒体库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('媒体库加载失败'), findsOneWidget);

    await tester.tap(find.text('去设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('服务器配置'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
