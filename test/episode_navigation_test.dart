import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/player/episode_navigation.dart';
import 'package:media_client/models/emby/emby_media_item.dart';

EmbyMediaItem _ep(String id, int? index) => EmbyMediaItem(
      id: id,
      name: 'E$id',
      type: 'Episode',
      indexNumber: index,
    );

void main() {
  group('sortEpisodesByIndex', () {
    test('sorts by indexNumber ascending', () {
      final sorted = sortEpisodesByIndex([_ep('c', 3), _ep('a', 1), _ep('b', 2)]);
      expect(sorted.map((e) => e.id).toList(), ['a', 'b', 'c']);
    });

    test('episodes without index sort to the end, keeping stability', () {
      final sorted = sortEpisodesByIndex(
        [_ep('x', null), _ep('a', 2), _ep('y', null), _ep('b', 1)],
      );
      expect(sorted.map((e) => e.id).toList(), ['b', 'a', 'x', 'y']);
    });

    test('returns a new list (input untouched)', () {
      final input = [_ep('b', 2), _ep('a', 1)];
      final sorted = sortEpisodesByIndex(input);
      expect(input.map((e) => e.id).toList(), ['b', 'a']);
      expect(sorted.map((e) => e.id).toList(), ['a', 'b']);
    });
  });

  group('adjacentEpisodesInSeason', () {
    final eps = [
      _ep('e1', 1),
      _ep('e2', 2),
      _ep('e3', 3),
      _ep('e4', 4),
    ];

    test('middle episode has both neighbors', () {
      final adj = adjacentEpisodesInSeason(eps, 'e2');
      expect(adj.previous?.id, 'e1');
      expect(adj.next?.id, 'e3');
    });

    test('first episode has no previous', () {
      final adj = adjacentEpisodesInSeason(eps, 'e1');
      expect(adj.previous, isNull);
      expect(adj.next?.id, 'e2');
    });

    test('last episode has no next', () {
      final adj = adjacentEpisodesInSeason(eps, 'e4');
      expect(adj.previous?.id, 'e3');
      expect(adj.next, isNull);
    });

    test('unknown id has no neighbors', () {
      final adj = adjacentEpisodesInSeason(eps, 'zz');
      expect(adj.previous, isNull);
      expect(adj.next, isNull);
    });

    test('single-episode season has neither', () {
      final adj = adjacentEpisodesInSeason([_ep('only', 1)], 'only');
      expect(adj.previous, isNull);
      expect(adj.next, isNull);
    });
  });
}
