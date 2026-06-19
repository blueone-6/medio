/// FFmpeg / mpv TCP read/write failures while streaming (e.g. 115 CDN).
bool isRecoverablePlayerNetworkError(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('ffurl_read') || lower.contains('ffurl_write')) {
    return true;
  }
  if (lower.startsWith('tcp:')) return true;
  return lower.contains('connection reset') ||
      lower.contains('connection aborted') ||
      lower.contains('connection timed out') ||
      lower.contains('network is unreachable');
}

String playerNetworkErrorFinalMessage(int maxAttempts) =>
    '网络不稳定，已自动重试 $maxAttempts 次仍无法继续播放';
