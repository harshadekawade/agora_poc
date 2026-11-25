import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/token_provider.dart';

/// Fetches tokens from the POC's local token server (`token_server/`).
class TokenServerClient implements TokenProvider {
  TokenServerClient({
    required Uri baseUrl,
    required http.Client httpClient,
    this.expireSeconds,
  }) : _baseUrl = baseUrl,
       _http = httpClient;

  static const _timeout = Duration(seconds: 8);

  final Uri _baseUrl;
  final http.Client _http;

  /// Short values make it easy to test token renewal mid-call.
  final int? expireSeconds;

  @override
  Future<String> rtcToken({required String channelId, required int uid}) async {
    final uri = _baseUrl.replace(
      path: '/rtc-token',
      queryParameters: {
        'channel': channelId,
        'uid': '$uid',
        if (expireSeconds != null) 'expire': '$expireSeconds',
      },
    );

    final http.Response response;
    try {
      response = await _http.get(uri).timeout(_timeout);
    } on Exception catch (error) {
      throw TokenUnavailableException(
        'Token server not reachable at $_baseUrl ($error)',
      );
    }

    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw TokenUnavailableException(
        'Token server sent a non-JSON reply (HTTP ${response.statusCode})',
      );
    }
    if (response.statusCode != 200) {
      final message = body is Map ? body['error'] : null;
      throw TokenUnavailableException(
        'Token server said HTTP ${response.statusCode}: ${message ?? 'no detail'}',
      );
    }
    final token = body is Map ? body['token'] : null;
    if (token is! String || token.isEmpty) {
      throw const TokenUnavailableException('Token server reply had no token');
    }
    return token;
  }
}

/// A console token (pasted in the app or built in). Works only for the
/// channel it was made for, and can't be renewed.
///
/// Reads the token on each request, so pasting a new one takes effect
/// without rebuilding anything that depends on this provider.
class StaticTokenProvider implements TokenProvider {
  const StaticTokenProvider(this._readToken);

  final String Function() _readToken;

  @override
  Future<String> rtcToken({
    required String channelId,
    required int uid,
  }) async => _readToken();
}
