/// 用户输入是否已包含 http/https 协议。
bool embyServerUrlHasScheme(String raw) {
  final lower = raw.trim().toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

/// 将用户输入规范化为可尝试的服务器根 URL 列表。
///
/// 未带协议时先尝试 https，再尝试 http。
/// 未带端口时使用各协议的标准端口（443 / 80），与改动前行为一致。
/// 已带协议时只返回一个候选地址。
List<String> embyServerUrlCandidates(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return [];

  if (embyServerUrlHasScheme(trimmed)) {
    final normalized = _normalizeWithScheme(trimmed);
    return normalized == null ? [] : [normalized];
  }

  final hostPart = trimmed.replaceAll(RegExp(r'/+$'), '');
  return [
    'https://$hostPart',
    'http://$hostPart',
  ];
}

String? _normalizeWithScheme(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final portPart = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path == '/' ? '' : uri.path.replaceAll(RegExp(r'/+$'), '');
  return '${uri.scheme}://${uri.host}$portPart$path';
}

/// 由服务器根 URL 构造 Emby API 根路径 `{server}/emby`。
String embyApiRootForServerUrl(String base) {
  final trimmed = base.trim();
  final withoutTrailing = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  final uri = Uri.parse(withoutTrailing);
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return '${uri.scheme}://${uri.host}$port$path/emby';
}
