import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/local_storage.dart';
import '../core/theme/app_theme.dart';
import '../services/emby_service.dart';
import '../services/player_service.dart';
import '../services/play_history_service.dart';
import '../services/playback_preferences_service.dart';
import '../services/settings_service.dart';

/// Overridden in [main] after [LocalStorage.open].
final localStorageProvider = Provider<LocalStorage>(
  (ref) => throw StateError('localStorageProvider not initialized'),
);

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService(ref.watch(localStorageProvider));
});

final playbackPreferencesServiceProvider =
    Provider<PlaybackPreferencesService>((ref) {
  return PlaybackPreferencesService(ref.watch(localStorageProvider));
});

final playHistoryServiceProvider = Provider<PlayHistoryService>((ref) {
  return PlayHistoryService(ref.watch(localStorageProvider));
});

final embyServiceProvider = Provider<EmbyService>((ref) {
  return EmbyService(ref.watch(settingsServiceProvider));
});

final playerServiceProvider = Provider<PlayerService>((ref) {
  final svc = PlayerService();
  ref.onDispose(svc.dispose);
  return svc;
});

// ── 主题 Providers ──

/// 当前主题配色方案（非 system 时有效）。
class ThemeVariantNotifier extends Notifier<AppThemeVariant> {
  @override
  AppThemeVariant build() {
    return ref.watch(settingsServiceProvider).themeVariant;
  }

  void set(AppThemeVariant variant) {
    state = variant;
  }
}

final themeVariantProvider =
    NotifierProvider<ThemeVariantNotifier, AppThemeVariant>(
  ThemeVariantNotifier.new,
);

/// 当前主题亮度模式。
class ThemeBrightnessNotifier extends Notifier<AppThemeBrightness> {
  @override
  AppThemeBrightness build() {
    return ref.watch(settingsServiceProvider).themeBrightness;
  }

  void set(AppThemeBrightness brightness) {
    state = brightness;
  }
}

final themeBrightnessProvider =
    NotifierProvider<ThemeBrightnessNotifier, AppThemeBrightness>(
  ThemeBrightnessNotifier.new,
);
