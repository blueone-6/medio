import 'package:media_kit/media_kit.dart';

/// Formats an [AudioTrack] into a human-readable label.
///
/// Priority: language > title > id fallback.
String audioTrackLabel(AudioTrack t) {
  final parts = <String>[];
  if (t.language != null && t.language!.isNotEmpty) {
    parts.add(t.language!);
  }
  if (t.title != null && t.title!.isNotEmpty) {
    parts.add(t.title!);
  }
  if (parts.isEmpty) {
    parts.add('音轨 ${t.id}');
  }
  return parts.join(' · ');
}