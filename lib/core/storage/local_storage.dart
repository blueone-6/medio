import 'package:shared_preferences/shared_preferences.dart';

abstract final class StorageKeys {
  static const embyServerUrl = 'emby_server_url';
  static const embyAccessToken = 'emby_access_token';
  static const embyUserId = 'emby_user_id';
  static const embyUserName = 'emby_user_name';
  static const embyApiKey = 'emby_api_key';
  static const embyClientDeviceId = 'emby_client_device_id';

  static const themeMode = 'theme_mode';
  static const themeVariant = 'theme_variant';
  static const themeBrightness = 'theme_brightness';
  static const localeCode = 'locale_code';
  static const defaultPlaybackSpeed = 'default_playback_speed';
  static const hardwareDecoding = 'hardware_decoding';
  static const subtitleFontSize = 'subtitle_font_size';
  static const subtitleOffsetMs = 'subtitle_offset_ms';
  static const homeRecentPlayLimit = 'home_recent_play_limit';
  static const autoPlayNext = 'auto_play_next';
  static const playHistory = 'play_history_json';
}

class LocalStorage {
  LocalStorage(
    this._prefs, {
    String keyPrefix = '',
  }) : _keyPrefix = keyPrefix;

  final SharedPreferences _prefs;
  final String _keyPrefix;

  static Future<LocalStorage> open() async {
    final p = await SharedPreferences.getInstance();
    return LocalStorage(p);
  }

  String _key(String key) => '$_keyPrefix$key';

  String? getString(String key) => _prefs.getString(_key(key));

  Future<void> setString(String key, String? value) async {
    final storageKey = _key(key);
    if (value == null) {
      await _prefs.remove(storageKey);
    } else {
      await _prefs.setString(storageKey, value);
    }
  }

  bool? getBool(String key) {
    final storageKey = _key(key);
    if (!_prefs.containsKey(storageKey)) return null;
    return _prefs.getBool(storageKey);
  }

  Future<void> setBool(String key, bool? value) async {
    final storageKey = _key(key);
    if (value == null) {
      await _prefs.remove(storageKey);
    } else {
      await _prefs.setBool(storageKey, value);
    }
  }

  double? getDouble(String key) {
    final storageKey = _key(key);
    if (!_prefs.containsKey(storageKey)) return null;
    return _prefs.getDouble(storageKey);
  }

  Future<void> setDouble(String key, double? value) async {
    final storageKey = _key(key);
    if (value == null) {
      await _prefs.remove(storageKey);
    } else {
      await _prefs.setDouble(storageKey, value);
    }
  }

  int? getInt(String key) {
    final storageKey = _key(key);
    if (!_prefs.containsKey(storageKey)) return null;
    return _prefs.getInt(storageKey);
  }

  Future<void> setInt(String key, int? value) async {
    final storageKey = _key(key);
    if (value == null) {
      await _prefs.remove(storageKey);
    } else {
      await _prefs.setInt(storageKey, value);
    }
  }

  Future<void> clearSession() async {
    await _prefs.remove(_key(StorageKeys.embyAccessToken));
    await _prefs.remove(_key(StorageKeys.embyUserId));
    await _prefs.remove(_key(StorageKeys.embyUserName));
  }
}
