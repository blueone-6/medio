import 'package:dio/dio.dart';

import '../core/api/api_exception.dart';

/// Coarse error category for UI affordances (secondary actions, hints).
enum UserFacingErrorKind {
  notConfigured,
  unauthorized,
  forbidden,
  notFound,
  network,
  timeout,
  server,
  rateLimited,
  cancelled,
  generic,
}

/// Structured copy for error surfaces (title, hint, settings CTA).
class UserFacingErrorInfo {
  const UserFacingErrorInfo({
    required this.kind,
    required this.message,
    this.title,
    this.hint,
  });

  final UserFacingErrorKind kind;
  final String message;
  final String? title;
  final String? hint;

  bool get suggestsSettings =>
      kind == UserFacingErrorKind.notConfigured ||
      kind == UserFacingErrorKind.unauthorized;

  UserFacingErrorInfo copyWith({
    UserFacingErrorKind? kind,
    String? message,
    String? title,
    String? hint,
  }) {
    return UserFacingErrorInfo(
      kind: kind ?? this.kind,
      message: message ?? this.message,
      title: title ?? this.title,
      hint: hint ?? this.hint,
    );
  }
}

/// Home sections that can fail independently on the PC feed.
enum HomeLoadSection {
  libraries,
  resume,
  recommendations,
}

/// Maps thrown errors to short, user-readable Chinese copy.
String userFacingMessage(Object error) => userFacingErrorInfo(error).message;

UserFacingErrorInfo userFacingErrorInfo(Object error) {
  if (error is ApiException) {
    return _apiExceptionInfo(error);
  }
  if (error is DioException) {
    return _dioInfo(error);
  }

  final text = error.toString();
  if (_containsAny(text, const [
    'SocketException',
    'Connection refused',
    'Connection reset',
    'Network is unreachable',
    'Failed host lookup',
    'HandshakeException',
  ])) {
    return const UserFacingErrorInfo(
      kind: UserFacingErrorKind.network,
      message: '无法连接服务器，请检查网络与服务器地址',
      hint: '确认电脑已联网，且 Emby 地址与端口填写正确',
    );
  }
  if (_containsAny(text, const ['TimeoutException', 'receive timeout', 'connection timeout'])) {
    return const UserFacingErrorInfo(
      kind: UserFacingErrorKind.timeout,
      message: '连接超时，请稍后重试',
      hint: '服务器响应较慢，可稍等片刻后再试',
    );
  }
  if (_containsAny(text, const ['401', 'Unauthorized', '未授权'])) {
    return const UserFacingErrorInfo(
      kind: UserFacingErrorKind.unauthorized,
      message: '登录已失效，请重新配置服务器',
      hint: '在设置中更新 API 密钥或重新登录',
    );
  }
  if (_containsAny(text, const ['403', 'Forbidden'])) {
    return const UserFacingErrorInfo(
      kind: UserFacingErrorKind.forbidden,
      message: '没有访问权限',
      hint: '请确认账号有权访问该媒体库',
    );
  }
  if (_containsAny(text, const ['404', 'Not Found'])) {
    return const UserFacingErrorInfo(
      kind: UserFacingErrorKind.notFound,
      message: '请求的内容不存在',
    );
  }
  if (_containsAny(text, const ['429', 'Too Many Requests', 'rate limit'])) {
    return const UserFacingErrorInfo(
      kind: UserFacingErrorKind.rateLimited,
      message: '请求过于频繁，请稍后再试',
    );
  }
  if (_containsAny(text, const ['500', '502', '503', '504'])) {
    return const UserFacingErrorInfo(
      kind: UserFacingErrorKind.server,
      message: '服务器暂时不可用，请稍后重试',
      hint: '若持续出现，请检查 Emby 服务是否正常运行',
    );
  }

  return const UserFacingErrorInfo(
    kind: UserFacingErrorKind.generic,
    message: '加载失败，请稍后重试',
  );
}

/// Section-specific title and hint layered on [userFacingErrorInfo].
UserFacingErrorInfo homeSectionErrorInfo(Object error, HomeLoadSection section) {
  final base = userFacingErrorInfo(error);
  final title = switch (section) {
    HomeLoadSection.libraries => '媒体库加载失败',
    HomeLoadSection.resume => '继续观看加载失败',
    HomeLoadSection.recommendations => '推荐内容加载失败',
  };

  final hint = switch ((base.kind, section)) {
    (UserFacingErrorKind.notConfigured, _) => '在设置中填写 Emby 服务器地址与 API 密钥',
    (UserFacingErrorKind.unauthorized, _) => '在设置中重新登录或更新 API 密钥',
    (UserFacingErrorKind.network, HomeLoadSection.recommendations) =>
      '续播区块可能仍可用，可先重试本区块或下拉刷新',
    (UserFacingErrorKind.network, HomeLoadSection.resume) =>
      '推荐区块可能仍可用，可先重试本区块或下拉刷新',
    (UserFacingErrorKind.network, HomeLoadSection.libraries) =>
      '确认网络正常后重试，或检查服务器地址',
    (UserFacingErrorKind.timeout, _) => '服务器响应较慢，稍等片刻后再试',
    (UserFacingErrorKind.server, _) => '若持续出现，请检查 Emby 服务状态',
    (UserFacingErrorKind.forbidden, HomeLoadSection.libraries) =>
      '请确认账号有权访问媒体库',
    _ => base.hint,
  };

  return base.copyWith(title: title, hint: hint);
}

UserFacingErrorInfo _apiExceptionInfo(ApiException e) {
  final configured = _isNotConfiguredMessage(e.message);
  if (configured) {
    return const UserFacingErrorInfo(
      kind: UserFacingErrorKind.notConfigured,
      message: '尚未配置 Emby 服务器',
      hint: '在设置中填写服务器地址与 API 密钥',
    );
  }

  final msg = e.message.trim();
  if (msg.isNotEmpty && !_looksTechnical(msg)) {
    return UserFacingErrorInfo(kind: _kindFromStatus(e.statusCode), message: msg);
  }

  if (e.statusCode != null) {
    return _infoFromStatus(e.statusCode);
  }
  final cause = e.cause;
  if (cause != null && cause is! ApiException) {
    return userFacingErrorInfo(cause);
  }
  return const UserFacingErrorInfo(
    kind: UserFacingErrorKind.generic,
    message: '加载失败，请稍后重试',
  );
}

UserFacingErrorInfo _dioInfo(DioException e) {
  return switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout =>
      const UserFacingErrorInfo(
        kind: UserFacingErrorKind.timeout,
        message: '连接超时，请稍后重试',
        hint: '服务器响应较慢，可稍等片刻后再试',
      ),
    DioExceptionType.connectionError => const UserFacingErrorInfo(
        kind: UserFacingErrorKind.network,
        message: '无法连接服务器，请检查网络与服务器地址',
        hint: '确认电脑已联网，且 Emby 地址与端口填写正确',
      ),
    DioExceptionType.badResponse => _infoFromStatus(e.response?.statusCode),
    DioExceptionType.cancel => const UserFacingErrorInfo(
        kind: UserFacingErrorKind.cancelled,
        message: '请求已取消',
      ),
    _ => userFacingErrorInfo(e.error ?? e),
  };
}

UserFacingErrorInfo _infoFromStatus(int? status) {
  final message = switch (status) {
    401 => '登录已失效，请重新配置服务器',
    403 => '没有访问权限',
    404 => '请求的内容不存在',
    429 => '请求过于频繁，请稍后再试',
    null => '加载失败，请稍后重试',
    >= 500 => '服务器暂时不可用，请稍后重试',
    _ => '加载失败，请稍后重试',
  };
  final hint = switch (status) {
    401 => '在设置中更新 API 密钥或重新登录',
    403 => '请确认账号有权访问该媒体库',
    final s? when s >= 500 => '若持续出现，请检查 Emby 服务是否正常运行',
    _ => null,
  };
  return UserFacingErrorInfo(
    kind: _kindFromStatus(status),
    message: message,
    hint: hint,
  );
}

UserFacingErrorKind _kindFromStatus(int? status) => switch (status) {
      401 => UserFacingErrorKind.unauthorized,
      403 => UserFacingErrorKind.forbidden,
      404 => UserFacingErrorKind.notFound,
      429 => UserFacingErrorKind.rateLimited,
      null => UserFacingErrorKind.generic,
      >= 500 => UserFacingErrorKind.server,
      _ => UserFacingErrorKind.generic,
    };

bool _isNotConfiguredMessage(String msg) {
  final lower = msg.toLowerCase();
  return lower.contains('not configured') ||
      lower.contains('url not configured') ||
      msg.contains('未配置');
}

bool _looksTechnical(String msg) =>
    msg.contains('Exception') || msg.startsWith('ApiException');

bool _containsAny(String haystack, List<String> needles) {
  for (final n in needles) {
    if (haystack.contains(n)) return true;
  }
  return false;
}
