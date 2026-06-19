import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/models/emby/emby_device_profile.dart';

void main() {
  test('android profile excludes TrueHD from direct play', () {
    final profile = buildEmbyDeviceProfile(android: true);
    final directProfiles = profile['DirectPlayProfiles'] as List<dynamic>;

    final mkvProfile = directProfiles.firstWhere(
      (p) => (p as Map)['Container'] == 'mkv',
    ) as Map;

    final audioCodec = mkvProfile['AudioCodec'] as String;
    expect(audioCodec.toLowerCase(), isNot(contains('truehd')));
    expect(audioCodec.toLowerCase(), isNot(contains('mlp')));
    expect(profile['TranscodingProfiles'], isNotEmpty);
  });

  test('desktop profile keeps TrueHD for mpv direct play', () {
    final profile = buildEmbyDeviceProfile(android: false);
    final directProfiles = profile['DirectPlayProfiles'] as List<dynamic>;

    final videoProfile = directProfiles.firstWhere(
      (p) => (p as Map)['Type'] == 'Video',
    ) as Map;

    final audioCodec = videoProfile['AudioCodec'] as String;
    expect(audioCodec.toLowerCase(), contains('truehd'));
  });
}
