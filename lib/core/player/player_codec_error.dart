/// FFmpeg / mpv decoder init failures for unsupported audio/video codecs.
bool isRecoverablePlayerCodecError(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('failed to initialize a decoder for codec')) {
    return true;
  }
  if (lower.contains('decoder') && lower.contains('not found')) {
    return true;
  }
  return lower.contains('codec not supported') ||
      lower.contains('no decoder for') ||
      lower.contains('unsupported codec') ||
      lower.contains('decoder init failed') ||
      lower.contains('mediacodec') ||
      lower.contains('format_supported');
}

String playerCodecErrorUserMessage(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('truehd')) {
    return '当前设备无法解码 TrueHD 音频，正在尝试服务器转码…';
  }
  if (lower.contains('dts')) {
    return '当前设备无法解码 DTS 音频，正在尝试服务器转码…';
  }
  if (isRecoverablePlayerCodecError(raw)) {
    return '当前设备不支持该音视频编码，正在尝试服务器转码…';
  }
  return raw;
}

String playerCodecErrorFinalMessage(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('truehd') || lower.contains('dts')) {
    return '当前设备无法播放该音频格式，请在 Emby 服务器启用转码后重试';
  }
  if (isRecoverablePlayerCodecError(raw)) {
    return '当前设备不支持该音视频编码，播放失败';
  }
  return raw;
}
