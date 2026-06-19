import 'package:flutter_test/flutter_test.dart';

import 'package:media_client/core/logging/perf.dart';

void main() {
  setUp(PerfTracer.clear);

  group('PerfTracer', () {
    test('start/end records a successful span with measured duration', () async {
      final span = PerfTracer.start('test.basic', context: {'k': 'v'});
      await Future<void>.delayed(const Duration(milliseconds: 25));
      span.end();

      final records = PerfTracer.recent();
      expect(records, hasLength(1));
      final r = records.first;
      expect(r.name, 'test.basic');
      expect(r.success, isTrue);
      expect(r.context['k'], 'v');
      expect(r.errorMessage, isNull);
      expect(r.durationMs, greaterThanOrEqualTo(20));
      expect(r.traceId, startsWith('test-'));
    });

    test('stage() captures incremental deltas, not absolute timestamps',
        () async {
      final span = PerfTracer.start('test.stages');
      await Future<void>.delayed(const Duration(milliseconds: 15));
      span.stage('s1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      span.stage('s2');
      span.end();

      final r = PerfTracer.recent().single;
      expect(r.stages.map((s) => s.name), ['s1', 's2']);
      // Each stage measures the delta from the previous mark, so neither
      // exceeds the others' wait. Allow slack for slow CI.
      expect(r.stages[0].elapsedMs, greaterThanOrEqualTo(10));
      expect(r.stages[1].elapsedMs, greaterThanOrEqualTo(15));
      expect(r.stages[1].elapsedMs, lessThan(100));
    });

    test('endError tags failure and captures truncated error text', () {
      final span = PerfTracer.start('test.boom');
      span.endError(Exception('something went wrong'));
      final r = PerfTracer.recent().single;
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('something went wrong'));
    });

    test('measure() wraps an async action and propagates errors', () async {
      final result = await PerfTracer.measure(
        'test.async.ok',
        () async => 42,
      );
      expect(result, 42);

      expect(
        () => PerfTracer.measure<int>('test.async.boom', () async {
          throw StateError('nope');
        }),
        throwsStateError,
      );
      // Give the rejected future a tick to record.
      await Future<void>.delayed(Duration.zero);

      final names = PerfTracer.recent().map((r) => r.name).toList();
      expect(names, containsAll(['test.async.ok', 'test.async.boom']));
      final failing = PerfTracer.recent()
          .firstWhere((r) => r.name == 'test.async.boom');
      expect(failing.success, isFalse);
    });

    test('end is idempotent (multiple .end() calls do not double-record)', () {
      final span = PerfTracer.start('test.idempotent');
      span.end();
      span.end();
      span.endError(Exception('ignored'));
      expect(PerfTracer.recent(), hasLength(1));
    });

    test('ring buffer caps at 200 entries, dropping oldest', () {
      for (var i = 0; i < 250; i++) {
        PerfTracer.start('test.fill.$i').end();
      }
      final recent = PerfTracer.recent();
      expect(recent.length, 200);
      // Newest first → top of ring is the very last one we pushed.
      expect(recent.first.name, 'test.fill.249');
    });

    test('recentMatching filters by name prefix', () {
      PerfTracer.start('player.bootstrap').end();
      PerfTracer.start('http.get').end();
      PerfTracer.start('player.seek').end();
      final players = PerfTracer.recentMatching('player.');
      expect(players.map((r) => r.name).toList(),
          ['player.seek', 'player.bootstrap']);
    });

    test('auto trace id derives type from dotted prefix', () {
      final span = PerfTracer.start('emby.getItem');
      span.end();
      expect(PerfTracer.recent().single.traceId, startsWith('emby-'));
    });
  });

  group('PerfFormat', () {
    test('stagesInline renders empty list as empty string', () {
      expect(PerfFormat.stagesInline([]), '');
    });

    test('stagesInline renders key:value pairs joined by comma', () {
      final s = PerfFormat.stagesInline([
        PerfStage('a', 10),
        PerfStage('b', 25),
      ]);
      expect(s, 'stages=[a:10ms, b:25ms]');
    });

    test('contextInline skips null values and truncates long strings', () {
      final s = PerfFormat.contextInline({
        'host': 'emby.local',
        'note': null,
        'big': 'x' * 200,
      });
      expect(s, contains('host=emby.local'));
      expect(s, isNot(contains('note=')));
      expect(s, contains('…'));
    });
  });
}
