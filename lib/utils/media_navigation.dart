import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/emby/emby_media_item.dart';
import '../services/emby_service.dart';
import 'player_route.dart';

Timer? _playMediaLockTimer;

/// 海报悬停播放：电影/单视频/分集直接播；电视剧则播「最早一季」的「第一集」（与详情页逻辑一致）。
Future<void> playMediaFromCard(
  BuildContext context,
  EmbyService emby,
  EmbyMediaItem m,
) async {
  if (_playMediaLockTimer != null && _playMediaLockTimer!.isActive) return;
  _playMediaLockTimer = Timer(const Duration(milliseconds: 800), () {});
  try {
    final t = m.type;
    if (t == 'Movie' || t == 'Video' || t == 'Episode') {
      if (!context.mounted) return;
      context.push(playerRouteForItem(m.id, item: m));
      return;
    }
    if (t == 'Series') {
      final ep = await emby.getFirstPlayableEpisodeForSeries(m.id);
      if (!context.mounted) return;
      if (ep != null) {
        context.push(playerRouteForItem(ep.id, item: ep));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无可播放剧集')),
        );
      }
      return;
    }
  } catch (_) {
    _playMediaLockTimer?.cancel();
    _playMediaLockTimer = null;
    rethrow;
  }
}

/// 首页 hub 海报：进入该条目的详情页。
void openHomeMediaItemDetail(BuildContext context, EmbyMediaItem m) {
  context.push('/item/${m.id}');
}

/// 媒体库网格：进入详情或子层级（文件夹进库、季进选集），不直接进播放器。
void openLibraryMediaItemDetail(
  BuildContext context,
  EmbyMediaItem m, {
  void Function(EmbyMediaItem folder)? onBrowseIntoFolder,
}) {
  final t = m.type;
  if (m.isLibraryBrowseCategory) {
    if (onBrowseIntoFolder != null) {
      onBrowseIntoFolder(m);
      return;
    }
    context.push(
      Uri(path: '/library/${m.id}', queryParameters: {'title': m.name}).toString(),
    );
    return;
  }
  if (t == 'Season') {
    final sid = m.seriesId;
    if (sid != null && sid.isNotEmpty) {
      context.push(
        Uri(
          path: '/item/$sid/season/${m.id}',
          queryParameters: {'name': m.name},
        ).toString(),
      );
      return;
    }
  }
  context.push('/item/${m.id}');
}

/// 是否显示 Emby 式「悬停播放」按钮（文件夹等不显示）。
bool embyItemSupportsGridPlay(EmbyMediaItem m) {
  final t = m.type;
  return t == 'Movie' || t == 'Series' || t == 'Episode' || t == 'Video';
}

void openSearchMediaItem(BuildContext context, EmbyMediaItem m) {
  final t = m.type;
  if (t == 'Movie' || t == 'Video' || t == 'Episode') {
    if (_playMediaLockTimer != null && _playMediaLockTimer!.isActive) return;
    _playMediaLockTimer = Timer(const Duration(milliseconds: 800), () {});
    context.push(playerRouteForItem(m.id, item: m));
    return;
  }
  context.push('/item/${m.id}');
}
