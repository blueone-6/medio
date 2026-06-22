@Tags(['integration'])
@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_client/core/player/apply_emby_subtitle.dart';
import 'package:media_client/core/player/player_subtitle_visibility.dart';
import 'package:media_client/core/player/subtitle_switch_queue.dart';
import 'package:media_client/core/storage/local_storage.dart';
import 'package:media_client/services/emby_service.dart';
import 'package:media_client/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real mpv integration: F1 狂飙飞车 (Emby item 2962) subtitle switching.
///
/// Run: flutter test test/subtitle_f1_integration_test.dart --tags integration
void main() {
  test('F1: all Emby subtitle options activate in mpv', () async {
    MediaKit.ensureInitialized();

    final prefsFile = File(
      '${Platform.environment['APPDATA']}'
      r'\com.example\media_client\shared_preferences.json',
    );
    expect(prefsFile.existsSync(), isTrue, reason: 'log in via app first');
    final stored = jsonDecode(prefsFile.readAsStringSync()) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues(
      stored.map((k, v) => MapEntry(k, v as Object)),
    );
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(LocalStorage(prefs));
    expect(settings.embyServerUrl, isNotNull);
    expect(settings.embyAccessToken, isNotNull);

    const itemId = '2962';
    final emby = EmbyService(settings);
    final pb = await emby.getPlaybackInfo(itemId, startTimeTicks: 0);

    final player = Player(configuration: const PlayerConfiguration(libass: true));
    addTearDown(() async {
      await player.dispose();
    });

    await player.open(Media(pb.streamUrl), play: false);
    await player.play();

    await player.stream.tracks
        .firstWhere(
          (t) =>
              t.subtitle.where((s) => s.id != 'auto' && s.id != 'no').length >=
              3,
        )
        .timeout(const Duration(seconds: 60));
    await player.configureMpvSubtitlesOnce();
    await Future<void>.delayed(const Duration(seconds: 3));

    final failures = <String>[];
    for (final option in pb.subtitles) {
      await SubtitleSwitchQueue.runSerial((gen) async {
        final ok = await applyEmbySubtitle(
          player: player,
          option: option,
          emby: emby,
          generation: gen,
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final sid = await player.mpvSubtitleId();
        final active = ok && sid != null && sid != 'no' && sid != 'auto';
        if (!active) {
          failures.add('index=${option.index} ${option.label} mpvSid=$sid ok=$ok');
        }
      });
    }

    expect(
      failures,
      isEmpty,
      reason: 'subtitle switches failed:\n${failures.join('\n')}',
    );
  }, timeout: const Timeout(Duration(minutes: 6)));
}
