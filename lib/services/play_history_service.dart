import 'dart:convert';

import '../core/storage/local_storage.dart';

/// One locally recorded play event for home recommendation seeds.
class PlayHistoryEntry {
  const PlayHistoryEntry({
    required this.itemId,
    required this.type,
    required this.playedAtMs,
    this.seriesId,
  });

  final String itemId;
  final String? seriesId;
  final String type;
  final int playedAtMs;

  /// Media-level id for recommendation seeds (series for episodes).
  String get mediaLevelId {
    if (type == 'Episode') {
      final sid = seriesId?.trim();
      if (sid != null && sid.isNotEmpty) return sid;
    }
    return itemId;
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        if (seriesId != null) 'seriesId': seriesId,
        'type': type,
        'playedAtMs': playedAtMs,
      };

  factory PlayHistoryEntry.fromJson(Map<String, dynamic> json) {
    return PlayHistoryEntry(
      itemId: json['itemId'] as String,
      seriesId: json['seriesId'] as String?,
      type: json['type'] as String? ?? 'Unknown',
      playedAtMs: (json['playedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Persists recent playback for F-I2 recommendation seeds.
class PlayHistoryService {
  PlayHistoryService(this._storage);

  final LocalStorage _storage;

  static const _maxEntries = 80;
  static const _debounceMs = 30 * 1000;

  String? _lastRecordedItemId;
  int _lastRecordedAtMs = 0;

  List<PlayHistoryEntry> get entries {
    final raw = _storage.getString(StorageKeys.playHistory);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list)
          if (e is Map<String, dynamic>) PlayHistoryEntry.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Recent unique media-level ids (newest first).
  List<String> recentMediaLevelIds({int limit = 5}) {
    final seen = <String>{};
    final ids = <String>[];
    for (final e in entries) {
      final id = e.mediaLevelId;
      if (seen.add(id)) ids.add(id);
      if (ids.length >= limit) break;
    }
    return ids;
  }

  Future<void> recordPlay({
    required String itemId,
    required String type,
    String? seriesId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastRecordedItemId == itemId && now - _lastRecordedAtMs < _debounceMs) {
      return;
    }
    _lastRecordedItemId = itemId;
    _lastRecordedAtMs = now;

    final next = [
      PlayHistoryEntry(
        itemId: itemId,
        seriesId: seriesId,
        type: type,
        playedAtMs: now,
      ),
      ...entries.where((e) => e.itemId != itemId),
    ];
    final trimmed = next.take(_maxEntries).toList();
    await _storage.setString(
      StorageKeys.playHistory,
      jsonEncode([for (final e in trimmed) e.toJson()]),
    );
  }
}
