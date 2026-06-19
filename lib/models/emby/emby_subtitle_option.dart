/// A subtitle track listed in Emby [PlaybackInfo] [MediaStreams].
///
/// Playback uses the dedicated subtitle stream API (not transcoding session URLs):
/// `GET /emby/Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/Stream.{format}`
class EmbySubtitleOption {
  const EmbySubtitleOption({
    required this.index,
    required this.label,
    required this.streamUrl,
    required this.format,
    this.language,
    this.isDefault = false,
    this.isForced = false,
    this.isExternal = false,
  });

  /// Emby media stream index (used in the Subtitles API path).
  final int index;

  /// Menu label (display title, language, or fallback).
  final String label;

  /// Emby `/Subtitles/{index}/Stream.{format}` URL; includes `api_key` when needed so mpv can load directly.
  final String streamUrl;

  /// Requested stream format extension: `srt`, `vtt`, or `ass`.
  final String format;

  final String? language;
  final bool isDefault;
  final bool isForced;
  final bool isExternal;

  /// Stable id for UI selection state.
  String get selectionId => 'emby:$index';

  /// Bitmap (PGS/PGSSUB) uses muxed mpv `sid`. Text uses Emby extract + `sub-add` (avoids `sid` stalls).
  bool get isBitmapSubtitle =>
      format == 'pgs' ||
      (label.toUpperCase().contains('PGSSUB')) ||
      (label.toUpperCase().contains('PGS'));

  /// ASS/SSA styled or bitmap subs — mpv can render; ExoPlayer cannot reliably.
  bool get isEffectSubtitle =>
      isBitmapSubtitle ||
      format == 'ass' ||
      format == 'ssa' ||
      label.contains('特效') ||
      label.toUpperCase().contains(' ASS');

  /// Text subtitle ExoPlayer can load via Emby extract (ASS is converted to SRT).
  bool get isExoPlayableTextSubtitle => !isBitmapSubtitle;

  /// Stream extension for ExoPlayer sidecar — never request `.ass` (effects break decode).
  String get exoStreamFormat {
    if (isBitmapSubtitle) return format;
    if (format == 'vtt') return 'vtt';
    return 'srt';
  }

  /// Emby subtitle URL with [exoStreamFormat] (ASS → SRT conversion on server).
  String get exoStreamUrl {
    final target = exoStreamFormat;
    final pattern = RegExp(r'/Stream\.([^./?]+)');
    if (pattern.hasMatch(streamUrl)) {
      return streamUrl.replaceFirst(pattern, '/Stream.$target');
    }
    return streamUrl;
  }
}
