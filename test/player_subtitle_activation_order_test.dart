@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import 'package:media_client/core/player/player_subtitle_visibility.dart';

class _RecordingNativePlayer extends NativePlayer {
  _RecordingNativePlayer() : super(configuration: const PlayerConfiguration());

  final List<String> calls = [];

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    calls.add('set:$property=$value');
  }

  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    if (property == 'time-pos') return '10';
    if (property == 'sid') return '5';
    if (property == 'track-list') return '[]';
    return '';
  }

  @override
  Future<void> command(
    List<String> command, {
    bool waitForInitialization = true,
  }) async {
    calls.add('command:${command.join(' ')}');
  }

  @override
  // ignore: must_call_super
  Future<void> dispose({bool synchronized = true}) async {}
}

void main() {
  test('muxed bitmap subtitle is selected after position restore', () async {
    MediaKit.ensureInitialized(
      libmpv: p.join(Directory.current.path, 'build', 'libmpv', 'libmpv-2.dll'),
    );
    final platform = _RecordingNativePlayer();
    final player = Player(platformPlayer: platform);
    addTearDown(player.dispose);

    const track = SubtitleTrack(
      '5',
      'Chinese (PGSSUB)',
      'chi',
      codec: 'hdmv_pgs_subtitle',
    );

    final ok = await player.activateMuxedSubtitle(track, reason: 'regression');

    expect(ok, isTrue);
    final relevant = platform.calls
        .where((call) =>
            call.startsWith('set:time-pos=') || call == 'command:set sid 5')
        .toList();
    expect(relevant, ['set:time-pos=10.001000', 'command:set sid 5']);
  });
}
