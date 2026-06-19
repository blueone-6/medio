import '../core/storage/local_storage.dart';

/// Persisted per-item playback UI choices (subtitle track, etc.).
class PlaybackPreferencesService {
  PlaybackPreferencesService(this._storage);

  final LocalStorage _storage;

  static const subtitleOff = 'no';
  static const subtitleAuto = 'auto';
  static const subtitleEmbyPrefix = 'emby:';
  static const subtitleTrackPrefix = 'track:';

  static String _subtitleKey(String itemId) => 'playback_subtitle_$itemId';
  static String _positionTicksKey(String itemId) => 'playback_position_ticks_$itemId';

  String? getSubtitleSelection(String itemId) =>
      _storage.getString(_subtitleKey(itemId));

  Future<void> setSubtitleSelection(String itemId, String? selection) =>
      _storage.setString(_subtitleKey(itemId), selection);

  int? getPlaybackPositionTicks(String itemId) =>
      _storage.getInt(_positionTicksKey(itemId));

  Future<void> setPlaybackPositionTicks(String itemId, int? ticks) =>
      _storage.setInt(_positionTicksKey(itemId), ticks);

  static String selectionForEmbyIndex(int index) => '$subtitleEmbyPrefix$index';

  static String selectionForTrack(String trackId) =>
      '$subtitleTrackPrefix$trackId';
}
