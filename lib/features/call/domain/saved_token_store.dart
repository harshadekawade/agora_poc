/// Keeps a token pasted in the app, so an expired console token can be
/// replaced without rebuilding the APK.
abstract interface class SavedTokenStore {
  String? read();

  Future<void> write(String token);

  Future<void> clear();
}
