import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureSessionStorage extends LocalStorage {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() => storage.read(key: supabasePersistSessionKey);
  @override
  Future<bool> hasAccessToken() =>
      storage.containsKey(key: supabasePersistSessionKey);
  @override
  Future<void> persistSession(String persistSessionString) => storage.write(
    key: supabasePersistSessionKey,
    value: persistSessionString,
  );
  @override
  Future<void> removePersistedSession() =>
      storage.delete(key: supabasePersistSessionKey);
}
