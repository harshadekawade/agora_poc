import 'package:shared_preferences/shared_preferences.dart';

import '../domain/saved_token_store.dart';

class SharedPrefsTokenStore implements SavedTokenStore {
  const SharedPrefsTokenStore(this._prefs);

  static const _key = 'agora_poc.saved_token';

  final SharedPreferences _prefs;

  @override
  String? read() => _prefs.getString(_key);

  @override
  Future<void> write(String token) => _prefs.setString(_key, token);

  @override
  Future<void> clear() => _prefs.remove(_key);
}
