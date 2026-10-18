import 'package:flutter_test/flutter_test.dart';

import 'package:media_client/core/player/exo/subtitle_text_parse.dart';

void main() {
  group('parseSubtitleText srt', () {
    test('parses basic blocks with comma and dot timestamps', () {
      const text = '1\n'
          '00:00:01,000 --> 00:00:02,500\n'
          'Hello\n'
          '\n'
          '2\n'
          '00:00:03.100 --> 00:00:04.900\n'
          'World\n'
          'Second line\n';
      final cues = parseSubtitleText(text, format: 'srt');
      expect(cues.length, 2);
      expect(cues[0].startMs, 1000);
      expect(cues[0].endMs, 2500);
      expect(cues[0].lines, ['Hello']);
      expect(cues[1].startMs, 3100);
      expect(cues[1].endMs, 4900);
      expect(cues[1].lines, ['World', 'Second line']);
    });

    test('strips inline markup', () {
      const text = '00:00:01,000 --> 00:00:02,000\n<i>Hello</i> <b>world</b>\n';
      final cues = parseSubtitleText(text, format: 'srt');
      expect(cues.single.lines.single, 'Hello world');
    });

    test('handles CRLF and BOM', () {
      const text = '\uFEFF1\r\n00:00:05,000 --> 00:00:06,000\r\n你好\r\n';
      final cues = parseSubtitleText(text, format: 'srt');
      expect(cues.single.lines.single, '你好');
      expect(cues.single.startMs, 5000);
    });

    test('skips malformed blocks', () {
      const text = 'not a cue\n\n00:00:01,000 --> 00:00:02,000\nok\n\n'
          '00:99:99,000 --> 00:00:03,000\nbad ts\n';
      final cues = parseSubtitleText(text, format: 'srt');
      expect(cues.length, 1);
      expect(cues.single.lines.single, 'ok');
    });

    test('skips zero-duration blocks', () {
      const text = '00:00:01,000 --> 00:00:01,000\nnope\n';
      expect(parseSubtitleText(text, format: 'srt'), isEmpty);
    });

    test('empty text yields no cues', () {
      expect(parseSubtitleText('', format: 'srt'), isEmpty);
      expect(parseSubtitleText('   \n \n', format: 'srt'), isEmpty);
    });
  });

  group('parseSubtitleText vtt', () {
    test('parses header, notes and hour-optional timestamps', () {
      const text = 'WEBVTT\n\n'
          'NOTE this is a comment\n\n'
          '00:01.000 --> 00:02.000 align:start\n'
          'First\n\n'
          'id-2\n'
          '01:00:01.500 --> 01:00:03.000\n'
          'Hour cue\n';
      final cues = parseSubtitleText(text, format: 'vtt');
      expect(cues.length, 2);
      expect(cues[0].startMs, 1000);
      expect(cues[0].endMs, 2000);
      expect(cues[0].lines, ['First']);
      expect(cues[1].startMs, 3601500);
      expect(cues[1].endMs, 3603000);
    });
  });

  group('activeSubtitleCue delay semantics', () {
    final cues = parseSubtitleText(
      '00:00:10,000 --> 00:00:12,000\nA\n\n'
      '00:00:20,000 --> 00:00:22,000\nB\n',
      format: 'srt',
    );

    test('no delay shows the cue covering the position', () {
      expect(activeSubtitleCue(cues, const Duration(seconds: 11), 0)?.lines, ['A']);
      expect(activeSubtitleCue(cues, const Duration(seconds: 21), 0)?.lines, ['B']);
      expect(activeSubtitleCue(cues, const Duration(seconds: 15), 0), isNull);
    });

    test('positive delay shows the cue active at position - delay', () {
      // Subtitles appear 3 s later: at t=13 the cue active at t=10 ("A") shows.
      expect(
        activeSubtitleCue(cues, const Duration(seconds: 13), 3000)?.lines,
        ['A'],
      );
      expect(activeSubtitleCue(cues, const Duration(seconds: 15), 3000), isNull);
    });

    test('negative delay shows the cue active at position + |delay|', () {
      // Subtitles appear 3 s earlier: at t=18 the cue active at t=21 ("B") shows.
      expect(
        activeSubtitleCue(cues, const Duration(seconds: 18), -3000)?.lines,
        ['B'],
      );
      expect(activeSubtitleCue(cues, const Duration(seconds: 15), -3000), isNull);
    });
  });
}
