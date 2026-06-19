/// 搜索/发现列表只展示电影与剧集（不含分集、季等）。
bool isEmbyCatalogMediaType(String type) => type == 'Movie' || type == 'Series';

/// Normalizes Emby / Jellyfin item [Type] from API JSON (string or [BaseItemKind] int).
String parseEmbyItemType(dynamic raw) {
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  if (raw is num) {
    return _baseItemKindName(raw.toInt()) ?? 'Unknown';
  }
  return 'Unknown';
}

/// Jellyfin [BaseItemKind] order (see jellyfin/Jellyfin.Data/Enums/BaseItemKind.cs).
String? _baseItemKindName(int value) {
  const names = [
    'AggregateFolder',
    'Audio',
    'AudioBook',
    'BasePluginFolder',
    'Book',
    'BoxSet',
    'Channel',
    'ChannelFolderItem',
    'CollectionFolder',
    'Episode',
    'Folder',
    'Genre',
    'ManualPlaylistsFolder',
    'Movie',
    'LiveTvChannel',
    'LiveTvProgram',
    'MusicAlbum',
    'MusicArtist',
    'MusicGenre',
    'MusicVideo',
    'Person',
    'Photo',
    'PhotoAlbum',
    'Playlist',
    'PlaylistsFolder',
    'Program',
    'Recording',
    'Season',
    'Series',
    'Studio',
    'Trailer',
    'TvChannel',
    'TvProgram',
    'UserRootFolder',
    'UserView',
    'Video',
    'Year',
  ];
  if (value < 0 || value >= names.length) return null;
  return names[value];
}

bool embyFieldsMatchSearchTerm(Iterable<String?> fields, String term) {
  final t = term.trim().toLowerCase();
  if (t.isEmpty) return false;
  for (final raw in fields) {
    if (raw != null && raw.toLowerCase().contains(t)) return true;
  }
  return false;
}
