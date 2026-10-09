import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/prefetch_suspend.dart';
import 'package:media_client/core/player/player_http_headers.dart';

void main() {
  group('prefetchSuspendMpvProperties', () {
    test('suspended zeroes both readahead windows', () {
      final props = prefetchSuspendMpvProperties(suspended: true);
      expect(props['cache-secs'], '0');
      expect(props['demuxer-readahead-secs'], '0');
    });

    test('restored returns the tuned stream-cache values', () {
      final props = prefetchSuspendMpvProperties(suspended: false);
      expect(props['cache-secs'], '$kStreamCacheSecs');
      expect(props['demuxer-readahead-secs'], '$kStreamDemuxerReadaheadSecs');
    });

    test('explicit values override the defaults', () {
      final props = prefetchSuspendMpvProperties(
        suspended: false,
        cacheSecs: 33,
        demuxerReadaheadSecs: 7,
      );
      expect(props['cache-secs'], '33');
      expect(props['demuxer-readahead-secs'], '7');
      // Suspension ignores the tuned values entirely.
      final suspended = prefetchSuspendMpvProperties(
        suspended: true,
        cacheSecs: 33,
        demuxerReadaheadSecs: 7,
      );
      expect(suspended['cache-secs'], '0');
      expect(suspended['demuxer-readahead-secs'], '0');
    });

    test('exposes exactly the two properties the open path tunes', () {
      final props = prefetchSuspendMpvProperties(suspended: false);
      expect(props.keys, unorderedEquals(['cache-secs', 'demuxer-readahead-secs']));
    });
  });
}
