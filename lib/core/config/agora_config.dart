/// Agora connection settings for the POC.
///
/// Values come from `--dart-define-from-file=agora.local.json` so the App ID
/// and token never live in source control. See `agora.local.example.json`.
/// The App Certificate is never here: only the token server has it.
class AgoraConfig {
  const AgoraConfig({
    required this.appId,
    required this.defaultChannelId,
    this.tokenServerUrl = '',
    this.staticToken = '',
    this.tokenExpirySeconds,
  });

  factory AgoraConfig.fromEnvironment() {
    const expiry = int.fromEnvironment('AGORA_TOKEN_EXPIRY_SECONDS');
    return const AgoraConfig(
      appId: String.fromEnvironment('AGORA_APP_ID'),
      defaultChannelId: String.fromEnvironment(
        'AGORA_CHANNEL',
        defaultValue: 'qispine-poc',
      ),
      tokenServerUrl: String.fromEnvironment('AGORA_TOKEN_SERVER_URL'),
      staticToken: String.fromEnvironment('AGORA_TOKEN'),
      tokenExpirySeconds: expiry > 0 ? expiry : null,
    );
  }

  final String appId;
  final String defaultChannelId;

  /// e.g. `http://127.0.0.1:8080` (USB + adb reverse) or the laptop's LAN IP.
  final String tokenServerUrl;

  /// Fallback: one console token, valid only for [defaultChannelId].
  final String staticToken;

  /// Ask the server for short-lived tokens to test renewal. Null = 1 hour.
  final int? tokenExpirySeconds;

  bool get usesTokenServer => tokenServerUrl.isNotEmpty;

  bool get isConfigured => appId.isNotEmpty && defaultChannelId.isNotEmpty;
}
