/// Issues Agora RTC tokens. In the real app this is the backend.
abstract interface class TokenProvider {
  Future<String> rtcToken({required String channelId, required int uid});
}

class TokenUnavailableException implements Exception {
  const TokenUnavailableException(this.message);
  final String message;

  @override
  String toString() => 'TokenUnavailableException: $message';
}
