import '../../utils/emby_item_type.dart';
import 'emby_person.dart';

/// Subset of Emby `BaseItemDto` used in lists and detail.
class EmbyMediaItem {
  const EmbyMediaItem({
    required this.id,
    required this.name,
    required this.type,
    this.overview,
    this.runTimeTicks,
    this.productionYear,
    this.seriesName,
    this.seasonName,
    this.parentIndexNumber,
    this.indexNumber,
    this.primaryImageTag,
    this.primaryImageItemId,
    this.parentThumbItemId,
    this.parentThumbImageTag,
    this.seriesPrimaryImageTag,
    this.logoImageTag,
    this.backdropImageTags,
    this.seriesId,
    this.seasonId,
    this.userDataPlayedPercentage,
    this.userDataPlayed,
    this.userDataPlaybackPositionTicks,
    this.productionLocations,
    this.communityRating,
    this.lastPlayedDate,
    this.people,
    this.genres,
    this.videoCodec,
    this.videoRange,
    this.audioCodec,
    this.isAtmos = false,
    this.videoHeight,
    this.videoWidth,
  });

  final String id;
  final String name;

  /// Emby type: Movie, Series, Season, Episode, Video, etc.
  final String type;
  final String? overview;
  final int? runTimeTicks;
  final int? productionYear;
  final String? seriesName;
  final String? seasonName;
  final int? parentIndexNumber;
  final int? indexNumber;
  final String? primaryImageTag;
  /// Emby 文件夹封面：指向子项（如文件夹内某部电影）的 Id，与 [primaryImageTag] 配合使用。
  final String? primaryImageItemId;
  /// 继承的 Thumb 图源（Emby 网页端文件夹封面常用）。
  final String? parentThumbItemId;
  final String? parentThumbImageTag;
  /// 剧集主海报 tag；分集常无自己的 [primaryImageTag]。
  final String? seriesPrimaryImageTag;
  /// Emby [ImageTags.Logo]：横版透明艺术字 / Logo。
  final String? logoImageTag;
  final List<String>? backdropImageTags;
  final String? seriesId;
  final String? seasonId;
  final double? userDataPlayedPercentage;
  final bool? userDataPlayed;
  final int? userDataPlaybackPositionTicks;
  final List<String>? productionLocations;
  final double? communityRating;
  final DateTime? lastPlayedDate;
  final List<EmbyPerson>? people;

  /// Emby [Genres] — 悬疑、剧情等，用于海报「类型」行。
  final List<String>? genres;

  /// 主视频流编解码（如 hevc、h264），来自 MediaStreams / MediaSources。
  final String? videoCodec;

  /// SDR / HDR / HDR10 / DolbyVision 等（Emby [VideoRange] / [VideoRangeType]）。
  final String? videoRange;

  /// 主音频编解码。
  final String? audioCodec;

  /// 是否含 Dolby Atmos 音轨。
  final bool isAtmos;

  /// 主视频流高度/宽度（像素）；列表项也可能仅在根字段提供。
  final int? videoHeight;
  final int? videoWidth;

  /// 2160p 及以上视为 4K。
  bool get isUhd4k {
    final h = videoHeight;
    final w = videoWidth;
    if (h != null && h >= 2160) return true;
    if (w != null && w >= 3840) return true;
    return false;
  }

  bool get isDolbyVision {
    final r = videoRange?.trim().toLowerCase() ?? '';
    if (r.contains('dolbyvision') || r == 'dv') return true;
    final c = videoCodec?.trim().toLowerCase() ?? '';
    return c.contains('dvhe') || c.contains('dav1');
  }

  bool get isHdr {
    if (isDolbyVision) return false;
    final r = videoRange?.trim().toLowerCase() ?? '';
    if (r.isEmpty || r == 'sdr') return false;
    return r.contains('hdr');
  }

  bool get isFolder =>
      type == 'Folder' || type == 'CollectionFolder' || type == 'UserView';

  /// 媒体库内可继续向下浏览的分类（含嵌套文件夹）。
  bool get isLibraryBrowseCategory {
    if (isFolder) return true;
    switch (type) {
      case 'AggregateFolder':
      case 'UserRootFolder':
      case 'BasePluginFolder':
        return true;
      default:
        return false;
    }
  }

  /// 是否可作为分类封面的子项（有主图/剧集图/背景图）。
  bool get hasLibraryCategoryCoverSeed {
    final primary = primaryImageTag?.trim();
    if (primary != null && primary.isNotEmpty) return true;
    final seriesPrimary = seriesPrimaryImageTag?.trim();
    if (seriesPrimary != null && seriesPrimary.isNotEmpty) return true;
    final backdrop = backdropImageTags;
    return backdrop != null && backdrop.isNotEmpty;
  }

  /// Emby / Jellyfin：Logo 可能在 [ImageTags.Logo]、[LogoImageTag] 或 [ImageInfos] 里。
  static String? logoTagFromJson(Map<String, dynamic> json) {
    final rawTags = json['ImageTags'];
    if (rawTags is Map) {
      final m = Map<String, dynamic>.from(
        rawTags.map((k, v) => MapEntry(k.toString(), v)),
      );
      for (final key in ['Logo', 'logo']) {
        final v = m[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
        if (v != null) {
          final s = v.toString().trim();
          if (s.isNotEmpty) return s;
        }
      }
    }
    final lt = json['LogoImageTag'];
    if (lt is String && lt.trim().isNotEmpty) return lt.trim();

    final infos = json['ImageInfos'];
    if (infos is List) {
      for (final e in infos) {
        if (e is! Map) continue;
        final map = Map<String, dynamic>.from(e);
        final rawType = map['ImageType'] ?? map['imageType'] ?? map['Type'] ?? map['type'];
        if (!_imageTypeIsLogo(rawType)) continue;
        final tag = map['ImageTag'] ?? map['imageTag'] ?? map['Tag'] ?? map['tag'];
        if (tag is String && tag.trim().isNotEmpty) return tag.trim();
      }
    }
    return null;
  }

  /// [ImageType.Logo]：服务端常返回字符串 `Logo`，也可能返回枚举整型（Jellyfin/Emby 多为 7）。
  static bool _imageTypeIsLogo(dynamic raw) {
    if (raw == null) return false;
    if (raw is num) {
      // MediaBrowser.Model.Entities.ImageType.Logo == 7（与 Jellyfin 一致）
      return raw == 7;
    }
    final s = raw.toString().trim().toLowerCase();
    if (s.contains('logo')) return true;
    final n = int.tryParse(s);
    return n == 7;
  }

  static int? _userDataInt(Map<String, dynamic>? userData, List<String> keys) {
    if (userData == null) return null;
    for (final k in keys) {
      final v = userData[k];
      if (v is num) return v.toInt();
    }
    return null;
  }

  static double? _userDataDouble(Map<String, dynamic>? userData, List<String> keys) {
    if (userData == null) return null;
    for (final k in keys) {
      final v = userData[k];
      if (v is num) return v.toDouble();
    }
    return null;
  }

  static Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return null;
  }

  /// `/Search/Hints` row (flat [SearchHint], no nested `Item`).
  factory EmbyMediaItem.fromSearchHintJson(Map<String, dynamic> json) {
    return EmbyMediaItem(
      id: _idFromJson(json),
      name: json['Name'] as String? ?? '',
      type: parseEmbyItemType(json['Type']),
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      seriesName: json['SeriesName'] as String? ??
          json['Series'] as String? ??
          json['series'] as String?,
      parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
      indexNumber: (json['IndexNumber'] as num?)?.toInt(),
      primaryImageTag: json['PrimaryImageTag'] as String?,
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
    );
  }

  static String _idFromJson(Map<String, dynamic> json) {
    final id = json['Id'] ?? json['ItemId'] ?? json['id'];
    if (id == null) return '';
    return id.toString();
  }

  static String? _readString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static int? _readInt(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toInt();
    }
    return null;
  }

  static bool _audioStreamIsAtmos(Map<String, dynamic> m) {
    final title = '${m['DisplayTitle'] ?? m['Title'] ?? m['displayTitle'] ?? ''}'
        .toLowerCase();
    if (title.contains('atmos')) return true;
    final codec = '${m['Codec'] ?? m['codec'] ?? ''}'.toLowerCase();
    if (codec.contains('atmos')) return true;
    final profile = '${m['Profile'] ?? m['profile'] ?? ''}'.toLowerCase();
    if (profile.contains('atmos')) return true;
    final extended = '${m['ExtendedAudioType'] ?? m['extendedAudioType'] ?? ''}'
        .toLowerCase();
    if (extended.contains('atmos')) return true;
    return false;
  }

  /// 从根 [MediaStreams] 或首个 [MediaSources] 条目解析视频/音频规格。
  static ({
    String? videoCodec,
    String? videoRange,
    String? audioCodec,
    bool isAtmos,
    int? videoHeight,
    int? videoWidth,
  }) _parseStreamInfo(Map<String, dynamic> json) {
    final streamMaps = <Map<String, dynamic>>[];

    void addStreams(dynamic raw) {
      if (raw is! List) return;
      for (final e in raw) {
        if (e is Map) {
          streamMaps.add(Map<String, dynamic>.from(e));
        }
      }
    }

    final sources = json['MediaSources'] ?? json['mediaSources'];
    Map<String, dynamic>? richestSource;
    var richestPixels = 0;
    if (sources is List) {
      for (final entry in sources) {
        if (entry is! Map) continue;
        final src = Map<String, dynamic>.from(entry);
        addStreams(src['MediaStreams'] ?? src['mediaStreams']);
        final h = _readInt(src, const ['Height', 'height']) ?? 0;
        final w = _readInt(src, const ['Width', 'width']) ?? 0;
        final pixels = h * w;
        if (pixels >= richestPixels) {
          richestPixels = pixels;
          richestSource = src;
        }
      }
    }
    if (streamMaps.isEmpty) {
      addStreams(json['MediaStreams'] ?? json['mediaStreams']);
    }

    String? videoCodec;
    String? videoRange;
    String? audioCodec;
    var atmos = false;
    int? videoHeight = _readInt(json, const ['Height', 'height']);
    int? videoWidth = _readInt(json, const ['Width', 'width']);

    if (richestSource != null) {
      videoHeight ??= _readInt(richestSource, const ['Height', 'height']);
      videoWidth ??= _readInt(richestSource, const ['Width', 'width']);
      videoCodec ??= _readString(richestSource, const ['VideoCodec', 'videoCodec']);
      videoRange ??= _readString(richestSource, const [
        'VideoRange',
        'videoRange',
        'VideoRangeType',
        'videoRangeType',
      ]);
    }

    for (final m in streamMaps) {
      final type = (_readString(m, const ['Type', 'type']) ?? '').toLowerCase();
      if (type == 'video') {
        videoCodec ??= _readString(m, const ['Codec', 'codec']);
        videoRange ??= _readString(m, const [
          'VideoRange',
          'videoRange',
          'VideoRangeType',
          'videoRangeType',
        ]);
        videoHeight ??= _readInt(m, const ['Height', 'height']);
        videoWidth ??= _readInt(m, const ['Width', 'width']);
      } else if (type == 'audio') {
        audioCodec ??= _readString(m, const ['Codec', 'codec']);
        if (_audioStreamIsAtmos(m)) atmos = true;
      }
    }

    return (
      videoCodec: videoCodec,
      videoRange: videoRange,
      audioCodec: audioCodec,
      isAtmos: atmos,
      videoHeight: videoHeight,
      videoWidth: videoWidth,
    );
  }

  factory EmbyMediaItem.fromJson(Map<String, dynamic> json) {
    final userData = _mapOrNull(json['UserData']);
    final imageTags = _mapOrNull(json['ImageTags']);
    final backdrop = json['BackdropImageTags'] as List<dynamic>?;
    final loc = json['ProductionLocations'] as List<dynamic>?;
    final lastPlayedRaw = userData?['LastPlayedDate'] as String?;
    final streamInfo = _parseStreamInfo(json);
    return EmbyMediaItem(
      id: _idFromJson(json),
      name: json['Name'] as String? ?? '',
      type: parseEmbyItemType(json['Type']),
      overview: json['Overview'] as String?,
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      seriesName: json['SeriesName'] as String? ??
          json['Series'] as String? ??
          json['series'] as String?,
      seasonName: json['SeasonName'] as String?,
      parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
      indexNumber: (json['IndexNumber'] as num?)?.toInt(),
      primaryImageTag: imageTags?['Primary'] as String? ??
          json['PrimaryImageTag'] as String?,
      primaryImageItemId: json['PrimaryImageItemId'] as String?,
      parentThumbItemId: json['ParentThumbItemId'] as String?,
      parentThumbImageTag: json['ParentThumbImageTag'] as String?,
      seriesPrimaryImageTag: json['SeriesPrimaryImageTag'] as String? ??
          json['seriesPrimaryImageTag'] as String?,
      logoImageTag: EmbyMediaItem.logoTagFromJson(json),
      backdropImageTags: backdrop?.map((e) => e.toString()).toList(),
      seriesId: json['SeriesId'] as String?,
      seasonId: json['SeasonId'] as String?,
      userDataPlayedPercentage: _userDataDouble(
        userData,
        const ['PlayedPercentage', 'playedPercentage'],
      ),
      userDataPlayed: userData?['Played'] as bool? ?? userData?['played'] as bool?,
      userDataPlaybackPositionTicks: _userDataInt(
        userData,
        const ['PlaybackPositionTicks', 'playbackPositionTicks'],
      ),
      productionLocations: loc?.map((e) => e.toString()).toList(),
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      lastPlayedDate:
          lastPlayedRaw != null ? DateTime.tryParse(lastPlayedRaw) : null,
      people: _parsePeople(json['People']),
      genres: _parseStringList(json['Genres']),
      videoCodec: streamInfo.videoCodec,
      videoRange: streamInfo.videoRange,
      audioCodec: streamInfo.audioCodec,
      isAtmos: streamInfo.isAtmos,
      videoHeight: streamInfo.videoHeight,
      videoWidth: streamInfo.videoWidth,
    );
  }

  static List<EmbyPerson>? _parsePeople(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;
    final list = <EmbyPerson>[];
    for (final e in raw) {
      if (e is Map<String, dynamic>) {
        list.add(EmbyPerson.fromJson(e));
      }
    }
    return list.isEmpty ? null : list;
  }

  static List<String>? _parseStringList(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;
    final out = <String>[];
    for (final e in raw) {
      final s = e?.toString().trim();
      if (s != null && s.isNotEmpty) out.add(s);
    }
    return out.isEmpty ? null : out;
  }
}

/// 列表 / 海报卡片上的可读标题（剧集分集带剧名）。
extension EmbyMediaItemDisplayTitles on EmbyMediaItem {
  /// 发现页风格卡片主标题：电影/剧集用 [name]，分集优先 [seriesName]。
  String get mediaCardDisplayTitle {
    if (type == 'Episode') {
      final sn = seriesName?.trim();
      if (sn != null && sn.isNotEmpty) return sn;
    }
    return name;
  }

  /// 海报角标：电影 / 剧集等。
  String get mediaTypeLabel {
    switch (type) {
      case 'Movie':
      case 'Video':
        return '电影';
      case 'Series':
        return '剧集';
      case 'Episode':
        return '剧集';
      case 'Season':
        return '季';
      default:
        return type;
    }
  }

  /// 海报右上角评分；无评分时返回 null。
  String? get mediaCardRatingText {
    final r = communityRating;
    if (r == null || r <= 0) return null;
    return r.toStringAsFixed(1);
  }

  /// 海报第一块：「剧名.季号」（如 `命运石之门.S1`），仅用 [parentIndexNumber]，不用 [seasonName]。
  String get mediaCardSeriesSeasonLine {
    if (type == 'Episode') {
      final sn = seriesName?.trim();
      if (sn != null && sn.isNotEmpty) {
        final p = parentIndexNumber;
        if (p != null) return '$sn.S$p';
        return sn;
      }
    }
    return name;
  }

  /// 海报第二块：「第N集.集名」；无剧名上下文的分集不返回（由第一块承担单行标题）。
  String? get mediaCardEpisodeLine {
    if (type != 'Episode') return null;
    final sn = seriesName?.trim();
    if (sn == null || sn.isEmpty) return null;
    return _episodeLine2();
  }

  /// 卡片底部：年份、评分等（不含剧名，避免与主标题块重复）。
  String? mediaCardMetaSubtitle({bool includeTypeFallback = false}) {
    final parts = <String>[
      if (productionYear != null) '$productionYear',
      if (communityRating != null) '★ ${communityRating!.toStringAsFixed(1)}',
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    if (includeTypeFallback && type == 'Episode' && (seriesName == null || seriesName!.trim().isEmpty)) {
      return type;
    }
    return null;
  }

  /// 搜索列表等用的副标题：类型 + 年份 + 评分。
  String mediaListSecondaryLine() {
    final meta = mediaCardMetaSubtitle() ?? '';
    if (meta.isEmpty) return type;
    return '$type · $meta';
  }

  /// 「第156集.本集标题」；无集号时仅本集标题。
  String _episodeLine2() {
    final ep = name.trim();
    final n = indexNumber;
    if (n != null) return '第$n集.$ep';
    return ep;
  }

  /// 次级继续观看卡：「第169集 · 38%」。
  String? get continueWatchingShortProgressLine {
    final pct = userDataPlayedPercentage;
    if (type == 'Episode') {
      final n = indexNumber;
      if (n != null && pct != null) return '第$n集 · ${pct.round()}%';
      if (n != null) return '第$n集';
    }
    if (pct != null) return '${pct.round()}%';
    return null;
  }

  /// 次级继续观看卡：「第169集 · 38%」。
  String? get continueWatchingCompactProgressLine {
    if (type == 'Episode') {
      final n = indexNumber;
      final pct = userDataPlayedPercentage;
      if (n != null && pct != null) return '第$n集 · ${pct.round()}%';
    }
    final pct = userDataPlayedPercentage;
    if (pct != null) return '${pct.round()}%';
    return null;
  }

  /// 继续观看进度行：「第271集 · 已观看 74%」。
  String? get continueWatchingProgressLine {
    final pct = userDataPlayedPercentage;
    if (type == 'Episode') {
      final n = indexNumber;
      if (n != null && pct != null) {
        return '第$n集 · 已观看 ${pct.round()}%';
      }
      if (n != null) return '第$n集';
    }
    if (pct != null) return '已观看 ${pct.round()}%';
    return null;
  }

  /// 最近播放列表：是否为剧集（分集或带剧名的 Video）。
  bool get isRecentPlaySeriesItem =>
      type == 'Episode' ||
      (type == 'Video' && (seriesName?.trim().isNotEmpty ?? false));

  /// 最近播放列表：是否为电影（含无剧名上下文的 Video）。
  bool get isRecentPlayMovieItem =>
      type == 'Movie' ||
      (type == 'Video' && (seriesName == null || seriesName!.trim().isEmpty));

  /// 最近播放列表副标题：进度 / 剩余时长 / 元信息。
  String recentPlayListSubtitle() {
    final parts = <String>[];
    final progress = continueWatchingProgressLine;
    if (progress != null) {
      parts.add(progress);
    }
    final remaining = remainingWatchLabel;
    if (remaining != null && (progress == null || !progress.contains(remaining))) {
      parts.add(remaining);
    }
    if (parts.isNotEmpty) return parts.join(' · ');
    return mediaListSecondaryLine();
  }

  /// 剩余观看时间文案；需 [runTimeTicks] 与 [userDataPlaybackPositionTicks]。
  String? get remainingWatchLabel {
    final total = runTimeTicks;
    final pos = userDataPlaybackPositionTicks;
    if (total == null || total <= 0 || pos == null) return null;
    final remaining = total - pos;
    if (remaining <= 0) return null;
    final minutes = (remaining / 600000000).ceil();
    if (minutes < 1) return '剩余不足 1 分钟';
    if (minutes < 60) return '剩余约 $minutes 分钟';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '剩余约 $hours 小时';
    return '剩余约 $hours 小时 $mins 分钟';
  }

  /// 海报「类型」行：最多 [max] 个流派，逗号分隔（不含电影/剧集，角标已展示）。
  String? mediaCardGenreLabels({int max = 2}) {
    final g = genres;
    if (g == null || g.isEmpty) return null;
    return g.take(max).join(', ');
  }

  /// 推荐区副标题（海报下方单行）：流派 / 年份 / 时长，不含类型角标信息。
  String get mediaCardRecommendSubtitle {
    final genreLine = mediaCardGenreLabels();
    if (genreLine != null) return genreLine;
    if (type == 'Movie' || type == 'Video') {
      final rt = runTimeTicks;
      if (rt != null && rt > 0) {
        final totalMin = (rt / 600000000).round();
        if (totalMin >= 60) {
          final h = totalMin ~/ 60;
          final m = totalMin % 60;
          return m > 0 ? '$h小时$m分' : '$h小时';
        }
        return '$totalMin分钟';
      }
    }
    if (productionYear != null) return '$productionYear';
    return '';
  }

  /// Dedup key for recommendation lists (episode → series).
  String get recommendDedupKey {
    if (type == 'Episode') {
      final sid = seriesId?.trim();
      if (sid != null && sid.isNotEmpty) return 'series:$sid';
    }
    return 'item:$id';
  }

  /// Normalize list item to media-level recommend entry (episode → series display).
  EmbyMediaItem toRecommendDisplayItem() {
    if (type != 'Episode') return this;
    final sid = seriesId?.trim();
    if (sid == null || sid.isEmpty) return this;
    return EmbyMediaItem(
      id: sid,
      name: seriesName?.trim().isNotEmpty == true ? seriesName!.trim() : name,
      type: 'Series',
      overview: overview,
      runTimeTicks: runTimeTicks,
      productionYear: productionYear,
      seriesName: seriesName,
      parentIndexNumber: parentIndexNumber,
      primaryImageTag: seriesPrimaryImageTag ?? primaryImageTag,
      seriesPrimaryImageTag: seriesPrimaryImageTag,
      backdropImageTags: backdropImageTags,
      seriesId: sid,
      userDataPlayedPercentage: userDataPlayedPercentage,
      userDataPlayed: userDataPlayed,
      communityRating: communityRating,
      productionLocations: productionLocations,
      genres: genres,
      videoCodec: videoCodec,
      videoRange: videoRange,
      audioCodec: audioCodec,
      isAtmos: isAtmos,
      videoHeight: videoHeight,
      videoWidth: videoWidth,
    );
  }
}