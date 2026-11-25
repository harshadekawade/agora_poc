import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/saved_token_store.dart';
import '../providers/call_providers.dart';

/// The token used when there is no token server: one pasted in the app
/// (saved on the phone), else the one built into the APK.
class ManualTokenController extends Notifier<String> {
  late SavedTokenStore _store;
  late String _builtInToken;

  @override
  String build() {
    _store = ref.watch(savedTokenStoreProvider);
    _builtInToken = ref.watch(agoraConfigProvider).staticToken;
    return _store.read() ?? _builtInToken;
  }

  bool get isUsingSavedToken => _store.read() != null;

  /// Saves a pasted token. Whitespace from copy-paste is removed, since
  /// Agora rejects a token with a stray space or line break.
  Future<void> save(String token) async {
    final cleaned = token.replaceAll(RegExp(r'\s'), '');
    if (cleaned.isEmpty) {
      await resetToBuiltIn();
      return;
    }
    await _store.write(cleaned);
    state = cleaned;
  }

  Future<void> resetToBuiltIn() async {
    await _store.clear();
    state = _builtInToken;
  }
}
