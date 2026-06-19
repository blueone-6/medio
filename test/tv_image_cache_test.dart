import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/tv/tv_image_cache.dart';

void main() {
  test('posterRequestMaxHeight clamps to display-aligned range', () {
    expect(TvImageCache.posterRequestMaxHeight(170), 213);
    expect(TvImageCache.posterRequestMaxHeight(80), 120);
    expect(TvImageCache.posterRequestMaxHeight(300), 240);
  });

  testWidgets('memCache poster px aligns to request size not display size', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(devicePixelRatio: 2),
          child: SizedBox.shrink(),
        ),
      ),
    );
    final context = tester.element(find.byType(SizedBox));
    expect(
      TvImageCache.memCachePosterHeightPx(context, 320),
      480,
    );
    expect(
      TvImageCache.memCachePosterWidthPx(context, 320),
      320,
    );
  });
}
