import 'dart:math';

import '../core/storage/local_storage.dart';
import '../core/theme/app_theme.dart';

/// Reads/writes app settings and Emby/integration endpoints.
class SettingsService {
  SettingsService(this._storage);

  final LocalStorage _storage;

  String? get embyServerUrl => _storage.getString(StorageKeys.embyServerUrl);

  Future<void> setEmbyServerUrl(String? v) =>
      _storage.setString(StorageKeys.embyServerUrl, v);

  String? get embyAccessToken =>
      _storage.getString(StorageKeys.embyAccessToken);

  Future<void> setEmbyAccessToken(String? v) =>
      _storage.setString(StorageKeys.embyAccessToken, v);

  String? get embyUserId => _storage.getString(StorageKeys.embyUserId);

  Future<void> setEmbyUserId(String? v) =>
      _storage.setString(StorageKeys.embyUserId, v);

  String? get embyUserName => _storage.getString(StorageKeys.embyUserName);

  Future<void> setEmbyUserName(String? v) =>
      _storage.setString(StorageKeys.embyUserName, v);

  String? get embyApiKey => _storage.getString(StorageKeys.embyApiKey);

  Future<void> setEmbyApiKey(String? v) =>
      _storage.setString(StorageKeys.embyApiKey, v);

  bool get hardwareDecoding =>
      _storage.getBool(StorageKeys.hardwareDecoding) ?? true;

  Future<void> setHardwareDecoding(bool v) =>
      _storage.setBool(StorageKeys.hardwareDecoding, v);

  double get defaultPlaybackSpeed =>
      _storage.getDouble(StorageKeys.defaultPlaybackSpeed) ?? 1.0;

  Future<void> setDefaultPlaybackSpeed(double v) =>
      _storage.setDouble(StorageKeys.defaultPlaybackSpeed, v);

  double get subtitleFontSize =>
      _storage.getDouble(StorageKeys.subtitleFontSize) ?? 48.0;

  Future<void> setSubtitleFontSize(double v) =>
      _storage.setDouble(StorageKeys.subtitleFontSize, v);

  int get subtitleOffsetMs =>
      _storage.getInt(StorageKeys.subtitleOffsetMs) ?? 0;

  Future<void> setSubtitleOffsetMs(int v) =>
      _storage.setInt(StorageKeys.subtitleOffsetMs, v);

  /// 首页「最近播放」条数上限（Emby `/Items/Resume` 的 `Limit`，1–50）。
  static const int homeRecentPlayLimitMin = 1;
  static const int homeRecentPlayLimitMax = 50;
  static const int homeRecentPlayLimitDefault = 30;

  int get homeRecentPlayLimit {
    final raw = _storage.getInt(StorageKeys.homeRecentPlayLimit);
    final v = raw ?? homeRecentPlayLimitDefault;
    return v.clamp(homeRecentPlayLimitMin, homeRecentPlayLimitMax);
  }

  Future<void> setHomeRecentPlayLimit(int v) => _storage.setInt(
        StorageKeys.homeRecentPlayLimit,
        v.clamp(homeRecentPlayLimitMin, homeRecentPlayLimitMax),
      );

  bool get autoPlayNext => _storage.getBool(StorageKeys.autoPlayNext) ?? true;

  Future<void> setAutoPlayNext(bool v) =>
      _storage.setBool(StorageKeys.autoPlayNext, v);

  // ── 主题设置 ──

  AppThemeVariant get themeVariant {
    final raw = _storage.getString(StorageKeys.themeVariant);
    if (raw == null) return AppThemeVariant.amber;
    return AppThemeVariant.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => AppThemeVariant.amber,
    );
  }

  Future<void> setThemeVariant(AppThemeVariant v) =>
      _storage.setString(StorageKeys.themeVariant, v.name);

  AppThemeBrightness get themeBrightness {
    final raw = _storage.getString(StorageKeys.themeBrightness);
    if (raw == null) return AppThemeBrightness.dark;
    return AppThemeBrightness.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => AppThemeBrightness.dark,
    );
  }

  Future<void> setThemeBrightness(AppThemeBrightness b) =>
      _storage.setString(StorageKeys.themeBrightness, b.name);

  Future<void> clearEmbySession() => _storage.clearSession();

  /// Stable UUID for `X-Emby-Authorization` → `DeviceId="..."`.
  Future<String> ensureEmbyClientDeviceId() async {
    var id = _storage.getString(StorageKeys.embyClientDeviceId);
    if (id == null || id.isEmpty) {
      id = _generateUuidV4();
      await _storage.setString(StorageKeys.embyClientDeviceId, id);
    }
    return id;
  }
}

String _generateUuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int v) => v.toRadixString(16).padLeft(2, '0');
  return '${h(b[0])}${h(b[1])}${h(b[2])}${h(b[3])}-'
      '${h(b[4])}${h(b[5])}-'
      '${h(b[6])}${h(b[7])}-'
      '${h(b[8])}${h(b[9])}-'
      '${h(b[10])}${h(b[11])}${h(b[12])}${h(b[13])}${h(b[14])}${h(b[15])}';
}
