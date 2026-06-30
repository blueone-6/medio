import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

import '../core/layout/platform_layout.dart';
import '../config/app_config.dart';
import '../core/logging/app_log.dart';
import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../core/api/api_interceptor.dart';
import '../models/emby/emby_device_profile.dart';
import '../models/emby/emby_library.dart';
import '../models/emby/emby_media_item.dart';
import '../models/emby/emby_person.dart';
import '../models/emby/emby_playback_info.dart';
import '../models/emby/emby_search_result.dart';
import '../models/emby/emby_user.dart';
import '../utils/emby_item_type.dart';
import '../utils/emby_server_url.dart';
import '../core/player/external_cdn_headers.dart';
import '../utils/playback_http_headers.dart';
import '../utils/stream_redirect.dart';
import 'settings_service.dart';

/// Emby REST client (paths relative to `{server}/emby`).
class EmbyService {
  EmbyService(this._settings) : _dio = createDio();

  final SettingsService _settings;
  final Dio _dio;

  String get _embyRoot {
    final base = _settings.embyServerUrl?.trim();
    if (base == null || base.isEmpty) {
      throw ApiException('Emby server URL not configured');
    }
    final uri = Uri.parse(base.endsWith('/') ? base.substring(0, base.length - 1) : base);
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}/emby';
  }

  Map<String, String> _authHeaders() {
    final token = _settings.embyAccessToken;
    final apiKey = _settings.embyApiKey;
    if (token != null && token.isNotEmpty) {
      return {'X-Emby-Token': token};
    }
    if (apiKey != null && apiKey.isNotEmpty) {
      return {'X-Emby-Token': apiKey};
    }
    return {};
  }

  String _embyDeviceLabel() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Other';
    }
  }

  /// [Emby / Jellyfin requirement](https://github.com/jellyfin/jellyfin/issues/14037):
  /// `Client` / `Device` / `DeviceId` / `Version` must be present or the server throws
  /// `ArgumentNullException` (e.g. `Parameter 'appName'`).
  String _xEmbyAuthorization(String deviceId) {
    final client = AppConfig.embyClientName.replaceAll('"', "'");
    final device = _embyDeviceLabel();
    final ver = AppConfig.embyClientVersion.replaceAll('"', "'");
    return 'MediaBrowser Client="$client", Device="$device", DeviceId="$deviceId", Version="$ver"';
  }

  Future<Map<String, String>> _embyRequestHeaders({bool includeAccessToken = true}) async {
    final deviceId = await _settings.ensureEmbyClientDeviceId();
    final headers = <String, String>{
      'X-Emby-Authorization': _xEmbyAuthorization(deviceId),
    };
    if (includeAccessToken) {
      headers.addAll(_authHeaders());
    }
    return headers;
  }

  Future<void> authenticate({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final candidates = embyServerUrlCandidates(serverUrl);
    if (candidates.isEmpty) {
      throw ApiException('请输入服务器地址');
    }

    ApiException? lastError;
    for (var i = 0; i < candidates.length; i++) {
      final url = candidates[i];
      final hasNext = i < candidates.length - 1;
      try {
        await _authenticateAtUrl(
          serverUrl: url,
          username: username,
          password: password,
        );
        return;
      } on ApiException catch (e) {
        lastError = e;
        if (hasNext && _shouldTryNextServerUrl(e)) continue;
        rethrow;
      }
    }
    throw lastError ?? ApiException('无法连接服务器，请检查地址与网络');
  }

  bool _shouldTryNextServerUrl(ApiException e) {
    final cause = e.cause;
    if (cause is DioException) return isTransientNetworkError(cause);
    return e.statusCode == null;
  }

  Future<void> _authenticateAtUrl({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    _dio.options.baseUrl = embyApiRootForServerUrl(serverUrl);
    try {
      final deviceId = await _settings.ensureEmbyClientDeviceId();
      final res = await _dio.post<Map<String, dynamic>>(
        '/Users/AuthenticateByName',
        data: {'Username': username, 'Pw': password},
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'X-Emby-Authorization': _xEmbyAuthorization(deviceId),
          },
        ),
      );
      final data = res.data;
      if (data == null) throw ApiException('Empty auth response');
      final access = data['AccessToken'] as String?;
      final userJson = data['User'] as Map<String, dynamic>?;
      if (access == null || userJson == null) {
        throw ApiException('Invalid auth response');
      }
      final user = EmbyUser.fromJson(userJson);
      await _settings.setEmbyServerUrl(serverUrl);
      await _settings.setEmbyAccessToken(access);
      await _settings.setEmbyUserId(user.id);
      await _settings.setEmbyUserName(user.name);
    } on DioException catch (e) {
      throwApiException(e);
    }
  }

  Future<List<EmbyLibrary>> getUserViews() async {
    final userId = _settings.embyUserId;
    if (userId == null) throw ApiException('Not logged in');
    _dio.options.baseUrl = _embyRoot;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/Users/$userId/Views',
        options: Options(headers: await _embyRequestHeaders()),
      );
      final items = res.data?['Items'] as List<dynamic>? ?? [];
      return items.map((e) => EmbyLibrary.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throwApiException(e);
    }
  }

  /// 含 [MediaSources]（内嵌 MediaStreams）供 F-C2 规格徽章解析；勿对单卡调 PlaybackInfo。
  static const _streamSpecFields = 'MediaSources,Height,Width';

  static const _listItemFields = 'Overview,PrimaryImageTag,PrimaryImageItemId,ParentThumbItemId,ParentThumbImageTag,'
      'BackdropImageTags,UserData,CommunityRating,ProductionLocations,Genres,'
      'SeriesId,SeriesPrimaryImageTag,SeriesName,SeasonName,ParentIndexNumber,IndexNumber,ImageTags,ImageInfos,'
      '$_streamSpecFields';

  Future<List<EmbyMediaItem>> getItems({
    String? parentId,
    int startIndex = 0,
    int limit = 50,
    String? includeItemTypes,
    bool recursive = false,
    String? sortBy,
    String? sortOrder,
    String? years,
    String? filters,
    String? searchTerm,
    bool enableUserData = false,
  }) async {
    final userId = _settings.embyUserId;
    if (userId == null) throw ApiException('Not logged in');
    _dio.options.baseUrl = _embyRoot;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/Users/$userId/Items',
        queryParameters: {
          if (parentId != null) 'ParentId': parentId,
          'StartIndex': startIndex,
          'Limit': limit,
          'Recursive': recursive,
          'Fields': _listItemFields,
          if (includeItemTypes != null) 'IncludeItemTypes': includeItemTypes,
          if (sortBy != null) 'SortBy': sortBy,
          if (sortOrder != null) 'SortOrder': sortOrder,
          if (searchTerm != null && searchTerm.trim().isNotEmpty) 'SearchTerm': searchTerm.trim(),
          if (years != null && years.isNotEmpty) 'Years': years,
          if (filters != null && filters.isNotEmpty) 'Filters': filters,
          if (enableUserData) 'EnableUserData': true,
        },
        options: Options(headers: await _embyRequestHeaders()),
      );
      final items = res.data?['Items'] as List<dynamic>? ?? [];
      return items.map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throwApiException(e);
    }
  }

  static const _libraryCoverSeedTypes = 'Movie,Series,Season,Episode,Video,BoxSet';

  /// Emby 网页端文件夹封面：优先 [EmbyMediaItem.primaryImageItemId] 指向的子项海报。
  String? libraryCategoryCoverUrl(EmbyMediaItem item, {int maxHeight = 320}) {
    final linkedId = item.primaryImageItemId?.trim();
    if (linkedId != null && linkedId.isNotEmpty) {
      final tag = item.primaryImageTag?.trim();
      return posterUrl(
        linkedId,
        tag: tag != null && tag.isNotEmpty ? tag : null,
        maxHeight: maxHeight,
      );
    }

    final thumbItemId = item.parentThumbItemId?.trim();
    if (thumbItemId != null && thumbItemId.isNotEmpty) {
      final thumbTag = item.parentThumbImageTag?.trim();
      return itemImageUrl(
        thumbItemId,
        'Thumb',
        tag: thumbTag != null && thumbTag.isNotEmpty ? thumbTag : null,
        maxHeight: maxHeight,
      );
    }

    final primary = item.primaryImageTag?.trim();
    if (primary != null && primary.isNotEmpty) {
      return posterUrl(item.id, tag: primary, maxHeight: maxHeight);
    }

    final backdrop = item.backdropImageTags;
    if (backdrop != null && backdrop.isNotEmpty) {
      return backdropUrl(item.id, tag: backdrop.first);
    }

    return null;
  }

  Future<List<EmbyMediaItem>> _getLatestInParent(String parentId, {int limit = 8}) async {
    final userId = _settings.embyUserId;
    if (userId == null) throw ApiException('Not logged in');
    _dio.options.baseUrl = _embyRoot;
    try {
      final res = await _dio.get<List<dynamic>>(
        '/Users/$userId/Items/Latest',
        queryParameters: {
          'ParentId': parentId,
          'Limit': limit,
          'Fields': _listItemFields,
        },
        options: Options(headers: await _embyRequestHeaders()),
      );
      final items = res.data ?? [];
      return items.map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throwApiException(e);
    }
  }

  Future<EmbyMediaItem?> getLibraryCategoryCoverItem(String parentId) async {
    final latest = _pickLibraryCategoryCoverSeed(
      await _getLatestInParent(parentId),
    );
    if (latest != null) return latest;

    final direct = _pickLibraryCategoryCoverSeed(
      await getItems(
        parentId: parentId,
        limit: 50,
        includeItemTypes: _libraryCoverSeedTypes,
        recursive: true,
        sortBy: 'SortName',
        sortOrder: 'Ascending',
      ),
    );
    if (direct != null) return direct;

    // 嵌套文件夹：子文件夹内可能才有剧集/电影（如 电视剧/国漫/xxx）。
    final children = await getItems(
      parentId: parentId,
      limit: 40,
      recursive: false,
      sortBy: 'SortName',
      sortOrder: 'Ascending',
    );
    for (final child in children) {
      if (!child.isLibraryBrowseCategory) continue;
      final nestedLatest = _pickLibraryCategoryCoverSeed(
        await _getLatestInParent(child.id),
      );
      if (nestedLatest != null) return nestedLatest;
      final nested = _pickLibraryCategoryCoverSeed(
        await getItems(
          parentId: child.id,
          limit: 30,
          includeItemTypes: _libraryCoverSeedTypes,
          recursive: true,
          sortBy: 'SortName',
          sortOrder: 'Ascending',
        ),
      );
      if (nested != null) return nested;
    }
    return null;
  }

  EmbyMediaItem? _pickLibraryCategoryCoverSeed(List<EmbyMediaItem> items) {
    if (items.isEmpty) return null;
    for (final item in items) {
      if (item.hasLibraryCategoryCoverSeed) return item;
    }
    return items.first;
  }

  Future<List<EmbyMediaItem>> getLatest({int limit = 24}) async {
    final userId = _settings.embyUserId;
    if (userId == null) throw ApiException('Not logged in');
    _dio.options.baseUrl = _embyRoot;
    try {
      final res = await _dio.get<List<dynamic>>(
        '/Users/$userId/Items/Latest',
        queryParameters: {
          'Limit': limit,
          'Fields': 'Overview,PrimaryImageTag,BackdropImageTags,UserData,Genres,ProductionYear',
        },
        options: Options(headers: await _embyRequestHeaders()),
      );
      final items = res.data ?? [];
      return items.map((e) => EmbyMediaItem.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throwApiException(e);
    }
  }

  /// “继续观看 / 最近播放” — Emby 文档要求以**用户**身份认证；部分版本在缺少
  /// [EnableUserData] 或 [IncludeItemTypes] 时 `/Items/Resume` 会返回空列表。
  /// 若仍为空，则回退到 `/Items?Recursive=true&Filters=IsResumable`（与网页常用查询一致）。
  Future<List<EmbyMediaItem>> getResume({int limit = 30}) async {
    final userId = _settings.embyUserId;
    if (userId == null) throw ApiException('Not logged in');
    _dio.options.baseUrl = _embyRoot;
    const resumeFields = 'Overview,PrimaryImageTag,BackdropImageTags,UserData,CommunityRating,ProductionYear,'
        'RunTimeTicks,SeriesName,SeasonName,ParentIndexNumber,IndexNumber,ImageTags,'
        'SeriesId,SeriesPrimaryImageTag,$_streamSpecFields';
    try {
      // 1. 获取"可续播"项目（部分观看 / Continue Watching）
      final resumableRes = await _dio.get<dynamic>(
        '/Users/$userId/Items/Resume',
        queryParameters: <String, dynamic>{
          'Limit': limit,
          'EnableUserData': true,
          'Fields': resumeFields,
          'IncludeItemTypes': 'Movie,Episode,Video',
        },
        options: Options(headers: await _embyRequestHeaders()),
      );
      final resumable = _parseUserItemsPayload(resumableRes.data);

      // 2. 获取"已看完"的最近播放项目（Played 但不再 Resumable）
      final playedRes = await _dio.get<dynamic>(
        '/Users/$userId/Items',
        queryParameters: <String, dynamic>{
          'Limit': limit,
          'Recursive': true,
          'EnableUserData': true,
          'Fields': resumeFields,
          'IncludeItemTypes': 'Movie,Episode,Video',
          'SortBy': 'DatePlayed',
          'SortOrder': 'Descending',
          'Filters': 'IsPlayed',
        },
        options: Options(headers: await _embyRequestHeaders()),
      );
      final played = _parseUserItemsPayload(playedRes);

      // 3. 合并两个列表：可续播放前面，已看完放后面，按 ID 去重
      final seen = <String>{};
      final merged = <EmbyMediaItem>[];
      for (final item in [...resumable, ...played]) {
        if (seen.add(item.id)) {
          merged.add(item);
        }
      }

      // 4. 统一按 DatePlayed 降序排列
      merged.sort(_compareLastPlayedDesc);

      if (merged.length <= limit) return merged;
      return merged.sublist(0, limit);
    } on DioException catch (e) {
      throwApiException(e);
    }
  }

  Future<List<EmbyMediaItem>> getSeasons(String seriesId) {
    return getItems(
      parentId: seriesId,
      includeItemTypes: 'Season',
      limit: 100,
    );
  }

  Future<List<EmbyMediaItem>> getEpisodes(String seasonId) {
    return getItems(
      parentId: seasonId,
      includeItemTypes: 'Episode',
      limit: 500,
      enableUserData: true,
    );
  }

  /// Returns the "Next Up" episode for a given series, or null if none.
  Future<EmbyMediaItem?> getNextUpForSeries(String seriesId) async {
    final userId = _settings.embyUserId;
    if (userId == null) throw ApiException('Not logged in');
    _dio.options.baseUrl = _embyRoot;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/Shows/NextUp',
        queryParameters: <String, dynamic>{
          'UserId': userId,
          'SeriesId': seriesId,
          'Limit': 1,
          'Fields': 'Overview,PrimaryImageTag,BackdropImageTags,UserData,CommunityRating,'
              'SeriesId,SeriesPrimaryImageTag,SeriesName,SeasonName,ParentIndexNumber,IndexNumber,ImageTags',
        },
        options: Options(headers: await _embyRequestHeaders()),
      );
      final items = res.data?['Items'] as List<dynamic>? ?? [];
      if (items.isEmpty) return null;
      return EmbyMediaItem.fromJson(items.first as Map<String, dynamic>);
    } on DioException catch (e) {
      throwApiException(e);
    }
  }

  /// First episode of the earliest numbered season (season index greater than 0), else specials / unindexed.
  Future<EmbyMediaItem?> getFirstPlayableEpisodeForSeries(String seriesId) async {
    final seasons = await getSeasons(seriesId);
    if (seasons.isEmpty) return null;
    final sortedSeasons = [...seasons]..sort((a, b) => (a.indexNumber ?? 1 << 20).compareTo(b.indexNumber ?? 1 << 20));
    final nonSpecial = sortedSeasons.where((s) => (s.indexNumber ?? 0) > 0).toList();
    final walk = nonSpecial.isNotEmpty ? nonSpecial : sortedSeasons;
    for (final season in walk) {
      final episodes = await getEpisodes(season.id);
      if (episodes.isEmpty) continue;
      final sortedEpisodes = [...episodes]..sort((a, b) => (a.indexNumber ?? 1 << 20).compareTo(b.indexNumber ?? 1 << 20));
      return sortedEpisodes.first;
    }
    return null;
  }

  /// Lightweight item fetch for player episode navigation (avoids heavy detail fields).
  static const _playerItemFields = 'RunTimeTicks,SeriesId,SeasonId,SeriesName,SeasonName,'
      'ParentIndexNumber,IndexNumber,UserData,'
      '$_streamSpecFields';

  Future<EmbyMediaItem> getItemForPlayer(String itemId) async {
    final userId = _settings.embyUserId;
    if (userId == null) throw ApiException('Not logged in');
    _dio.options.baseUrl = _embyRoot;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/Users/$userId/Items/$itemId',
        queryParameters: {'Fields': _playerItemFields},
        options: Options(headers: await _embyRequestHeaders()),
      );
      final data = res.data;
      if (data == null) throw ApiException('Empty item');
      return EmbyMediaItem.fromJson(data);
    } on DioException catch (e) {
      throwApiException(e);
    }
  }

  Future<EmbyMediaItem> getItem(String itemId) async {
    final userId = _settings.embyUserId;
    if (userId == null) throw ApiException('Not logged in');
    _dio.options.baseUrl = _embyRoot;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/Users/$userId/Items/$itemId',
        queryParameters: {
          'Fields': 'Overview,PrimaryImageTag,BackdropImageTags,UserData,People,Genres,ProviderIds,'
              'RunTimeTicks,SeriesId,SeriesPrimaryImageTag,SeriesName,SeasonName,'
              'ParentIndexNumber,IndexNumber,ImageTags,ImageInfos,$_streamSpecFields',
        },
        options: Options(headers: await _embyRequestHeaders()),
      );
      final data = res.data;
      if (data == null) throw ApiException('Empty item');
      return EmbyMediaItem.fromJson(data);
    } on DioException catch (e) {
      throwApiException(e);
    }
  }

  /// User playback state (position, played %, resumable flag).
  Future<Map<String, dynamic>?> getUserData(String itemId) async {
    final userId = _settings.embyUserId;
    if (userId == null) throw ApiException('Not logged in');
    _dio.options.baseUrl = _embyRoot;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/Users/$userId/Items/$itemId/UserData',
        options: Options(headers: await _embyRequestHeaders()),
      );
      return res.data;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // Some Emby builds only expose UserData on the item DTO, not this route.
      if (code == 404 || code == 405 || code == 400) return null;
      throwApiException(e);
    }
  }

  /// GET `/stream` with playback headers; follows redirect chain
  /// to the final CDN URL.
  ///
  /// Some servers return a single CDN Location;
  /// server-side strm plugins may return an intermediate `redirect_url` hop —
  /// both are resolved here before mpv open.
  Future<String> resolveExternalCdnUrl(String embyStreamUrl) async {
    final headers = isExternalCdnPlaybackUrl(embyStreamUrl)
        ? externalCdnPlaybackHttpHeaders()
        : const <String, String>{};
    final resolved = await resolvePlaybackRedirectChain(
      embyStreamUrl,
      requestHeaders: headers,
    );
    AppLog.instance.i(
      'ExtCdn',
      'resolve ${AppLog.redactUrl(resolved)}',
    );
    return resolved;
  }

  /// Auth / CDN headers for [media_kit] playback.
  Map<String, String>? playbackStreamHttpHeaders(
    String streamUrl, {
    bool strmViaEmbyProxy = false,
  }) {
    if (strmViaEmbyProxy) {
      if (isExternalCdnPlaybackUrl(streamUrl)) {
        return externalCdnPlaybackHttpHeaders();
      }
      return null;
    }
    final base = _settings.embyServerUrl?.trim();
    if (base == null || base.isEmpty) return null;
    final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final token = _settings.embyAccessToken ?? _settings.embyApiKey;
    return playbackHttpHeaders(
      streamUrl,
      embyServerBase: normalized,
      embyToken: token,
    );
  }

  Future<List<EmbySearchHint>> searchHints(String term, {int limit = 30}) async {
    final userId = _settings.embyUserId;
    if (userId == null) throw ApiException('Not logged in');
    _dio.options.baseUrl = _embyRoot;
    try {
      final res = await _dio.get<dynamic>(
        '/Search/Hints',
        queryParameters: {
          'SearchTerm': term,
          'UserId': userId,
          'Limit': limit,
          'IncludeItemTypes': 'Movie,Series',
        },
        options: Options(headers: await _embyRequestHeaders()),
      );
      final hints = _parseSearchHintsPayload(res.data);
      var results = [
        for (final e in hints)
          if (e is Map) EmbySearchHint.fromJson(Map<String, dynamic>.from(e)),
      ];
      results = _catalogSearchHintsOnly(results);
      // Hints 为空时回退到全库 Items 搜索（支持子串；Emby 部分版本要求 ≥2 字）。
      if (results.isEmpty && term.trim().isNotEmpty) {
        final items = await searchItemsByTerm(term, limit: limit);
        results = [for (final i in items) EmbySearchHint(item: i)];
      }
      return results;
    } on DioException catch (e) {
      throwApiException(e);
    } catch (e) {
      throw ApiException('Failed to parse search results', cause: e);
    }
  }

  /// 全库子串搜索：`/Users/{id}/Items?SearchTerm=&Recursive=true`。
  Future<List<EmbyMediaItem>> searchItemsByTerm(
    String term, {
    int limit = 100,
    String includeItemTypes = 'Movie,Series',
  }) async {
    final userId = _settings.embyUserId;
    if (userId == null) throw ApiException('Not logged in');
    _dio.options.baseUrl = _embyRoot;
    try {
      final res = await _dio.get<dynamic>(
        '/Users/$userId/Items',
        queryParameters: {
          'SearchTerm': term,
          'Recursive': true,
          'Limit': limit,
          'IncludeItemTypes': includeItemTypes,
          'Fields': 'Overview,PrimaryImageTag,BackdropImageTags,UserData,CommunityRating,ProductionLocations,'
              'SeriesId,SeriesPrimaryImageTag,SeriesName,SeasonName,ParentIndexNumber,IndexNumber,ImageTags,ImageInfos,'
              '$_streamSpecFields',
        },
        options: Options(headers: await _embyRequestHeaders()),
      );
      return _parseUserItemsPayload(res.data).where((m) => isEmbyCatalogMediaType(m.type)).toList();
    } on DioException catch (e) {
      throwApiException(e);
    }
  }

  Future<EmbyPlaybackInfo> getPlaybackInfo(
    String itemId, {
    int startTimeTicks = 0,
  }) async {
    final userId = _settings.embyUserId;
    if (userId == null) throw ApiException('Not logged in');
    _dio.options.baseUrl = _embyRoot;
    final body = {
      'UserId': userId,
      'MaxStreamingBitrate': 140000000,
      'StartTimeTicks': startTimeTicks,
      'DeviceProfile': buildEmbyDeviceProfile(android: isAndroidMobileUi),
    };
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/Items/$itemId/PlaybackInfo',
        queryParameters: {'UserId': userId},
        data: body,
        options: Options(headers: await _embyRequestHeaders()),
      );
      final data = res.data;
      if (data == null) throw ApiException('Empty PlaybackInfo');
      final base = _settings.embyServerUrl?.trim();
      if (base == null || base.isEmpty) {
        throw ApiException('Emby server URL not configured');
      }
      final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      final token = _settings.embyAccessToken ?? _settings.embyApiKey;

      // Strm: mpv opens /stream once, follows 307 to the final CDN (do not pre-resolve CDN in Dio).
      final strmProxy = playbackSourcesNeedStreamProxy(data, normalized);
      final serverStartTicks = strmProxy ? 0 : startTimeTicks;

      final raw = EmbyPlaybackInfo.fromResponse(
        data,
        itemId: itemId,
        serverPublicBase: normalized,
        accessToken: token,
        startTimeTicks: serverStartTicks,
      );
      var streamUrl = resolvePlaybackStreamUrl(
        info: raw,
        itemId: itemId,
        serverPublicBase: normalized,
        accessToken: token,
        startTimeTicks: strmProxy ? null : (startTimeTicks > 0 ? startTimeTicks : null),
      );
      if (streamUrl == raw.streamUrl && !strmProxy) {
        return raw;
      }
      return EmbyPlaybackInfo(
        playSessionId: raw.playSessionId,
        mediaSourceId: raw.mediaSourceId,
        streamUrl: streamUrl,
        subtitles: raw.subtitles,
        supportsDirectPlay: raw.supportsDirectPlay,
        directStreamUrl: raw.directStreamUrl,
        transcodingUrl: raw.transcodingUrl,
        fallbackStreamUrl: raw.fallbackStreamUrl,
        runTimeTicks: raw.runTimeTicks,
        strmViaEmbyStream: strmProxy,
      );
    } on DioException catch (e) {
      throwApiException(e);
    }
  }

  /// Notifies Emby that playback started — POST /Sessions/Playing (no EventName).
  Future<void> reportPlaybackStarted({
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required int positionTicks,
  }) async {
    final userId = _settings.embyUserId;
    if (userId == null) return;
    _dio.options.baseUrl = _embyRoot;
    final body = _playbackBaseBody(
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      playSessionId: playSessionId,
      positionTicks: positionTicks,
      isPaused: false,
    );
    try {
      await _dio.post(
        '/Sessions/Playing',
        data: body,
        options: Options(headers: await _embyRequestHeaders()),
      );
      AppLog.instance.i('Playback', 'Started itemId=$itemId psid=$playSessionId');
    } on DioException catch (e) {
      AppLog.instance.w(
        'Playback',
        'Started FAILED itemId=$itemId status=${e.response?.statusCode} '
            'body=${e.response?.data} msg=${e.message}',
      );
    }
  }

  /// Reports playback position to Emby/Jellyfin — POST /Sessions/Playing/Progress.
  Future<void> reportProgress({
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required int positionTicks,
    required bool isPaused,
  }) async {
    final userId = _settings.embyUserId;
    if (userId == null) return;
    _dio.options.baseUrl = _embyRoot;
    final body = {
      ..._playbackBaseBody(
        itemId: itemId,
        mediaSourceId: mediaSourceId,
        playSessionId: playSessionId,
        positionTicks: positionTicks,
        isPaused: isPaused,
      ),
      'EventName': isPaused ? 'Pause' : 'TimeUpdate',
    };
    try {
      await _dio.post(
        '/Sessions/Playing/Progress',
        data: body,
        options: Options(headers: await _embyRequestHeaders()),
      );
    } on DioException catch (e) {
      AppLog.instance.w(
        'Playback',
        'Progress FAILED itemId=$itemId status=${e.response?.statusCode} '
            'body=${e.response?.data} msg=${e.message}',
      );
    }
  }

  /// Notifies Emby that playback stopped — POST /Sessions/Playing/Stopped.
  Future<void> reportPlaybackStopped({
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required int positionTicks,
  }) async {
    final userId = _settings.embyUserId;
    if (userId == null) return;
    _dio.options.baseUrl = _embyRoot;
    final body = _playbackBaseBody(
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      playSessionId: playSessionId,
      positionTicks: positionTicks,
      isPaused: true,
    );
    try {
      await _dio.post(
        '/Sessions/Playing/Stopped',
        data: body,
        options: Options(headers: await _embyRequestHeaders()),
      );
      AppLog.instance.i('Playback', 'Stopped itemId=$itemId ticks=$positionTicks');
    } on DioException catch (e) {
      AppLog.instance.w(
        'Playback',
        'Stopped FAILED itemId=$itemId status=${e.response?.statusCode} '
            'body=${e.response?.data} msg=${e.message}',
      );
    }
  }

  /// Shared request body for all three playback check-in endpoints.
  /// See https://dev.emby.media/doc/restapi/Playback-Check-ins.html
  Map<String, dynamic> _playbackBaseBody({
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required int positionTicks,
    required bool isPaused,
  }) {
    final userId = _settings.embyUserId;
    return {
      'QueueableMediaTypes': ['Audio', 'Video'],
      'CanSeek': true,
      'ItemId': itemId,
      'MediaSourceId': mediaSourceId,
      'IsPaused': isPaused,
      'IsMuted': false,
      'PositionTicks': positionTicks,
      'VolumeLevel': 100,
      'PlayMethod': 'DirectPlay',
      'PlaySessionId': playSessionId,
      'PlaylistIndex': 0,
      'PlaylistLength': 1,
      'PlaybackRate': 1,
      if (userId != null) 'UserId': userId,
    };
  }

  String? posterUrl(String itemId, {String? tag, int maxHeight = 320}) {
    return itemImageUrl(itemId, 'Primary', tag: tag, maxHeight: maxHeight);
  }

  String? itemImageUrl(
    String itemId,
    String imageType, {
    String? tag,
    int maxHeight = 320,
    int index = 0,
  }) {
    final base = _settings.embyServerUrl?.trim();
    if (base == null || base.isEmpty) return null;
    final uri = Uri.parse(base.endsWith('/') ? base.substring(0, base.length - 1) : base);
    final pathSuffix = imageType == 'Backdrop' ? '/emby/Items/$itemId/Images/Backdrop/$index' : '/emby/Items/$itemId/Images/$imageType';
    final root = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '${uri.path}$pathSuffix',
      queryParameters: {
        if (tag != null) 'tag': tag,
        if (imageType != 'Backdrop') 'maxHeight': '$maxHeight',
      },
    );
    return root.toString();
  }

  /// 列表海报：分集若无自己的 Primary，则用剧集 [seriesId] + [seriesPrimaryImageTag]。
  String? posterUrlForItem(EmbyMediaItem item, {int maxHeight = 320}) {
    if (item.type == 'Episode') {
      final own = item.primaryImageTag?.trim();
      if (own != null && own.isNotEmpty) {
        return posterUrl(item.id, tag: own, maxHeight: maxHeight);
      }
      final sid = item.seriesId?.trim();
      if (sid != null && sid.isNotEmpty) {
        final st = item.seriesPrimaryImageTag?.trim();
        return posterUrl(sid, tag: (st != null && st.isNotEmpty) ? st : null, maxHeight: maxHeight);
      }
    }
    return posterUrl(item.id, tag: item.primaryImageTag, maxHeight: maxHeight);
  }

  String? backdropUrl(
    String itemId, {
    String? tag,
    int index = 0,
    int? maxWidth,
    int? maxHeight,
  }) {
    final base = _settings.embyServerUrl?.trim();
    if (base == null || base.isEmpty) return null;
    final uri = Uri.parse(base.endsWith('/') ? base.substring(0, base.length - 1) : base);
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '${uri.path}/emby/Items/$itemId/Images/Backdrop/$index',
      queryParameters: {
        if (tag != null) 'tag': tag,
        if (maxWidth != null) 'maxWidth': '$maxWidth',
        if (maxHeight != null) 'maxHeight': '$maxHeight',
      },
    ).toString();
  }

  /// 详情页背景：分集常无 Backdrop，回退到 [seriesParent] 或 [seriesId]（与 [logoUrlForItem] 一致）。
  String? backdropUrlForItem(
    EmbyMediaItem item, {
    EmbyMediaItem? seriesParent,
    int index = 0,
    int? maxWidth,
    int? maxHeight,
  }) {
    final ownTags = item.backdropImageTags;
    if (ownTags != null && ownTags.isNotEmpty) {
      final tag = index < ownTags.length ? ownTags[index] : ownTags.first;
      return backdropUrl(
        item.id,
        tag: tag,
        index: index,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
    }
    if (seriesParent != null) {
      final parentTags = seriesParent.backdropImageTags;
      if (parentTags != null && parentTags.isNotEmpty) {
        final tag = index < parentTags.length ? parentTags[index] : parentTags.first;
        return backdropUrl(
          seriesParent.id,
          tag: tag,
          index: index,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        );
      }
    }
    if (item.type == 'Episode') {
      final sid = item.seriesId?.trim();
      if (sid != null && sid.isNotEmpty) {
        return backdropUrl(
          sid,
          tag: null,
          index: index,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        );
      }
    }
    return backdropUrl(
      item.id,
      tag: null,
      index: index,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  /// Emby 网页端「艺术字」：[ImageTags.Logo] 透明横版图。
  String? logoUrl(
    String itemId, {
    String? tag,
    int maxHeight = 128,
    int maxWidth = 560,
  }) {
    final base = _settings.embyServerUrl?.trim();
    if (base == null || base.isEmpty) return null;
    final uri = Uri.parse(base.endsWith('/') ? base.substring(0, base.length - 1) : base);
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '${uri.path}/emby/Items/$itemId/Images/Logo',
      queryParameters: {
        if (tag != null && tag.isNotEmpty) 'tag': tag,
        'maxHeight': '$maxHeight',
        'maxWidth': '$maxWidth',
      },
    ).toString();
  }

  /// 详情页 Logo：有 [EmbyMediaItem.logoImageTag] 时带 tag；分集无 Logo 时用剧集 Id。
  /// 剧集/电影等常**不在 DTO 里写出 Logo tag**，但 `/Images/Logo` 仍可用，故无 tag 时也请求默认 Logo。
  String? logoUrlForItem(EmbyMediaItem item, {int maxHeight = 128, int maxWidth = 560}) {
    final id = item.id.trim();
    if (id.isEmpty) return null;

    final own = item.logoImageTag?.trim();
    if (own != null && own.isNotEmpty) {
      return logoUrl(id, tag: own, maxHeight: maxHeight, maxWidth: maxWidth);
    }
    if (item.type == 'Episode') {
      final sid = item.seriesId?.trim();
      if (sid != null && sid.isNotEmpty) {
        return logoUrl(sid, tag: null, maxHeight: maxHeight, maxWidth: maxWidth);
      }
    }
    const typesWithDefaultLogo = {
      'Series',
      'Movie',
      'Season',
      'BoxSet',
      'Video',
    };
    if (typesWithDefaultLogo.contains(item.type)) {
      return logoUrl(id, tag: null, maxHeight: maxHeight, maxWidth: maxWidth);
    }
    return null;
  }

  Map<String, String> get imageAuthHeaders {
    final token = _settings.embyAccessToken ?? _settings.embyApiKey;
    if (token == null || token.isEmpty) return {};
    return {'X-Emby-Token': token};
  }

  /// In-memory cache for downloaded external subtitle text (URL → content).
  final Map<String, String> _subtitleCache = {};

  /// Downloads an external subtitle file from the given absolute URL and returns its text content.
  Future<String?> fetchSubtitleText(String url) async {
    final cached = _subtitleCache[url];
    if (cached != null) return cached;
    try {
      final res = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: await _embyRequestHeaders(),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );
      if (res.statusCode == 200 && res.data != null && res.data!.isNotEmpty) {
        _subtitleCache[url] = res.data!;
        AppLog.instance.d('EmbyService', 'fetchSubtitleText ok bytes=${res.data!.length}');
        return res.data;
      }
      AppLog.instance.w(
        'EmbyService',
        'fetchSubtitleText empty status=${res.statusCode} url=${AppLog.redactUrl(url)}',
      );
      return null;
    } on DioException catch (e, st) {
      AppLog.instance.e(
        'EmbyService',
        'fetchSubtitleText failed url=${AppLog.redactUrl(url)}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<List<EmbyPerson>> getItemPeople(String itemId) async {
    _dio.options.baseUrl = _embyRoot;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/Items/$itemId/People',
        queryParameters: {'Limit': '20'},
        options: Options(headers: await _embyRequestHeaders()),
      );
      final items = res.data?['Items'] as List<dynamic>? ?? [];
      return [
        for (final e in items)
          if (e is Map<String, dynamic>) EmbyPerson.fromJson(e),
      ];
    } on DioException catch (e) {
      AppLog.instance.w(
        'Emby',
        'getItemPeople error: ${e.response?.statusCode} ${e.message}',
      );
      return [];
    }
  }

  Future<List<EmbyMediaItem>> getSimilarItems(String itemId, {int limit = 12}) async {
    final userId = _settings.embyUserId;
    _dio.options.baseUrl = _embyRoot;
    try {
      final params = <String, dynamic>{
        'Limit': '$limit',
        'Fields': 'Overview,PrimaryImageTag,ProductionYear,CommunityRating,Genres',
      };
      if (userId != null && userId.isNotEmpty) {
        params['UserId'] = userId;
      }
      final res = await _dio.get<Map<String, dynamic>>(
        '/Items/$itemId/Similar',
        queryParameters: params,
        options: Options(headers: await _embyRequestHeaders()),
      );
      final items = res.data?['Items'] as List<dynamic>? ?? [];
      return [
        for (final e in items)
          if (e is Map<String, dynamic>) EmbyMediaItem.fromJson(e),
      ];
    } on DioException catch (e) {
      AppLog.instance.w(
        'Emby',
        'getSimilarItems error: ${e.response?.statusCode} ${e.message}',
      );
      return [];
    }
  }
}

List<EmbySearchHint> _catalogSearchHintsOnly(List<EmbySearchHint> hints) {
  return [
    for (final h in hints)
      if (isEmbyCatalogMediaType(h.item.type)) h,
  ];
}

/// Emby: `{ "SearchHints": [...] }`；部分 Jellyfin/插件直接返回 `[...]` 或 `{ "Items": [...] }`。
List<dynamic> _parseSearchHintsPayload(dynamic data) {
  if (data is List) return data;
  if (data is Map) {
    final m = Map<String, dynamic>.from(data);
    for (final key in ['SearchHints', 'searchHints', 'Items', 'items']) {
      final raw = m[key];
      if (raw is List) return raw;
    }
  }
  return [];
}

List<EmbyMediaItem> _parseUserItemsPayload(dynamic data) {
  if (data is List) {
    return [
      for (final e in data)
        if (e is Map) EmbyMediaItem.fromJson(Map<String, dynamic>.from(e)),
    ];
  }
  if (data is Map) {
    final m = Map<String, dynamic>.from(data);
    final raw = m['Items'] ?? m['items'];
    if (raw is List) {
      return [
        for (final e in raw)
          if (e is Map) EmbyMediaItem.fromJson(Map<String, dynamic>.from(e)),
      ];
    }
  }
  return [];
}

int _compareLastPlayedDesc(EmbyMediaItem a, EmbyMediaItem b) {
  final ta = a.lastPlayedDate;
  final tb = b.lastPlayedDate;
  if (ta == null && tb == null) return 0;
  if (ta == null) return 1;
  if (tb == null) return -1;
  return tb.compareTo(ta);
}
