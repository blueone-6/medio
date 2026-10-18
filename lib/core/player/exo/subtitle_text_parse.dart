/// Parses external subtitle text (SRT / WebVTT) fetched from the Emby
/// Subtitles stream API into a full cue timeline.
///
/// The ExoPlayer phone path renders external subtitles with a Flutter overlay
/// (instead of a MediaItem sidecar) so the cue timeline is fully known
/// client-side — that is what enables both-direction subtitle delay and
/// letterbox-aware positioning, matching the mpv path's capabilities.
library;

class ParsedSubtitleCue {
  const ParsedSubtitleCue({
    required this.startMs,
    required this.endMs,
    required this.lines,
  });

  final int startMs;
  final int endMs;
  final List<String> lines;

  bool covers(int ms) => ms >= startMs && ms < endMs;
}

/// Parses [text] as [format] (`srt` or `vtt`) into a cue list sorted by start
/// time. Malformed blocks are skipped; an empty/unknown input yields `[]`.
List<ParsedSubtitleCue> parseSubtitleText(String text, {required String format}) {
  final normalized = text.replaceAll('\uFEFF', '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.trim().isEmpty) return const [];
  final lower = format.toLowerCase();
  final parser = lower == 'vtt' ? _VttBlocks() : _SrtBlocks();
  final cues = <ParsedSubtitleCue>[];
  for (final block in _splitBlocks(normalized)) {
    final cue = _parseBlock(block, parser);
    if (cue != null) cues.add(cue);
  }
  cues.sort((a, b) => a.startMs.compareTo(b.startMs));
  return cues;
}

List<String> _splitBlocks(String text) {
  final blocks = <String>[];
  final lines = text.split('\n');
  final current = <String>[];
  for (final line in lines) {
    if (line.trim().isEmpty) {
      if (current.isNotEmpty) blocks.add(current.join('\n'));
      current.clear();
    } else {
      current.add(line);
    }
  }
  if (current.isNotEmpty) blocks.add(current.join('\n'));
  return blocks;
}

class _SrtBlocks {
  // SRT blocks: optional numeric index line, then `start --> end`.
}

class _VttBlocks {
  // VTT blocks: optional `id` line, `start --> end` with optional settings
  // (align/line/position) after the end timestamp.
}

int? _parseTimestamp(String raw, bool vtt) {
  var t = raw.trim();
  if (t.isEmpty) return null;
  // "00:00:01.000" / "00:00:01,000" / "00:01.000" (VTT hour-optional)
  final m = RegExp(
    vtt
        ? r'^(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{1,3})$'
        : r'^(\d+):(\d{1,2}):(\d{2})[.,](\d{1,3})$',
  ).firstMatch(t);
  if (m == null) return null;
  int group(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  if (vtt) {
    final hours = group(1);
    final minutes = group(2);
    final seconds = group(3);
    var ms = group(4);
    final digits = (m.group(4) ?? '').length;
    // ".5" means 500ms; ".500" also 500ms — scale by digit count.
    for (var i = digits; i < 3; i++) {
      ms *= 10;
    }
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + ms;
  }
  final hours = group(1);
  final minutes = group(2);
  final seconds = group(3);
  var ms = group(4);
  final digits = (m.group(4) ?? '').length;
  for (var i = digits; i < 3; i++) {
    ms *= 10;
  }
  return ((hours * 60 + minutes) * 60 + seconds) * 1000 + ms;
}

ParsedSubtitleCue? _parseBlock(String block, Object parser) {
  final vtt = parser is _VttBlocks;
  final lines = block.split('\n');
  if (lines.isEmpty) return null;

  var headerIndex = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains('-->')) {
      headerIndex = i;
      break;
    }
  }
  if (headerIndex < 0) return null;

  final parts = lines[headerIndex].split('-->');
  if (parts.length < 2) return null;
  final start = _parseTimestamp(parts[0], vtt);
  // Strip VTT cue settings ("... align:start position:10%") from the end.
  var endRaw = parts[1].trim();
  final space = endRaw.indexOf(' ');
  if (space > 0) endRaw = endRaw.substring(0, space);
  final end = _parseTimestamp(endRaw, vtt);
  if (start == null || end == null || end <= start) return null;

  final textLines = lines
      .skip(headerIndex + 1)
      .map((l) => _stripMarkup(l))
      .where((l) => l.isNotEmpty)
      .toList();
  if (textLines.isEmpty) return null;

  return ParsedSubtitleCue(startMs: start, endMs: end, lines: textLines);
}

/// Removes inline markup common in SRT/VTT (bold/italic/font tags) so the
/// overlay renders clean text like mpv's default subtitle style.
String _stripMarkup(String line) {
  var out = line.replaceAll(RegExp(r'</?[a-zA-Z][^>]*>'), '');
  out = out.replaceAll(RegExp(r'</\s*[a-zA-Z][^>]*>'), '');
  return out.trim();
}

/// Finds the cue that should be displayed at [position] with [delayMs] applied
/// (mpv `sub-delay` semantics: positive delay shows the cue [delayMs] later,
/// i.e. the cue active at `position - delayMs`).
ParsedSubtitleCue? activeSubtitleCue(
  List<ParsedSubtitleCue> cues,
  Duration position,
  int delayMs,
) {
  if (cues.isEmpty) return null;
  final effectiveMs = position.inMilliseconds - delayMs;
  // Binary search for the last cue with startMs <= effectiveMs.
  var lo = 0;
  var hi = cues.length - 1;
  var candidate = -1;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    if (cues[mid].startMs <= effectiveMs) {
      candidate = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  if (candidate < 0) return null;
  final cue = cues[candidate];
  return cue.covers(effectiveMs) ? cue : null;
}
