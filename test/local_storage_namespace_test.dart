import 'package:flutter_test/flutter_test.dart';
import 'package:media_client/core/storage/local_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LocalStorage namespace', () {
    test('stores and reads values', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await LocalStorage.open();

      await storage.setString(StorageKeys.embyServerUrl, 'https://example.com');

      expect(storage.getString(StorageKeys.embyServerUrl), 'https://example.com');
    });

    test('clearSession only clears session keys', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await LocalStorage.open();

      await storage.setString(StorageKeys.embyAccessToken, 'token');
      await storage.setString(StorageKeys.embyServerUrl, 'https://example.com');

      await storage.clearSession();

      expect(storage.getString(StorageKeys.embyAccessToken), isNull);
      expect(storage.getString(StorageKeys.embyServerUrl), 'https://example.com');
    });
  });
}
