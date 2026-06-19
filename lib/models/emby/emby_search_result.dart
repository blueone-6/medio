import 'emby_media_item.dart';

/// Search hint row from `/Search/Hints`.
class EmbySearchHint {
  const EmbySearchHint({
    required this.item,
  });

  final EmbyMediaItem item;

  factory EmbySearchHint.fromJson(Map<String, dynamic> json) {
    final rawItem = json['Item'] ?? json['item'];
    if (rawItem is Map) {
      return EmbySearchHint(
        item: EmbyMediaItem.fromJson(Map<String, dynamic>.from(rawItem)),
      );
    }
    // Jellyfin/Emby SearchHint: flat object with Type / Series / PrimaryImageTag.
    return EmbySearchHint(
      item: EmbyMediaItem.fromSearchHintJson(json),
    );
  }
}
