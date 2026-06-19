import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/models/emby/emby_media_item.dart';
import 'package:media_client/widgets/media_badges.dart';

void main() {
  test('parses 4K HDR Atmos from MediaSources MediaStreams', () {
    final item = EmbyMediaItem.fromJson({
      'Id': '1',
      'Name': 'Test Movie',
      'Type': 'Movie',
      'MediaSources': [
        {
          'Id': 'ms1',
          'Height': 2160,
          'Width': 3840,
          'MediaStreams': [
            {
              'Type': 'Video',
              'Codec': 'hevc',
              'Height': 2160,
              'Width': 3840,
              'VideoRange': 'HDR10',
            },
            {
              'Type': 'Audio',
              'Codec': 'truehd',
              'DisplayTitle': 'English Dolby Atmos 7.1',
            },
          ],
        },
      ],
    });

    final badges = item.mediaSpecBadges;
    expect(badges, contains(MediaSpecBadge.uhd4k));
    expect(badges, contains(MediaSpecBadge.hdr));
    expect(badges, contains(MediaSpecBadge.atmos));
  });

  test('parses Dolby Vision from VideoRange', () {
    final item = EmbyMediaItem.fromJson({
      'Id': '2',
      'Name': 'DV Movie',
      'Type': 'Movie',
      'Height': 2160,
      'MediaSources': [
        {
          'MediaStreams': [
            {
              'Type': 'Video',
              'Codec': 'hevc',
              'Height': 2160,
              'VideoRange': 'DolbyVision',
            },
          ],
        },
      ],
    });

    expect(item.mediaSpecBadges, contains(MediaSpecBadge.uhd4k));
    expect(item.mediaSpecBadges, contains(MediaSpecBadge.dolbyVision));
    expect(item.mediaSpecBadges, isNot(contains(MediaSpecBadge.hdr)));
  });
}
