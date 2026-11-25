import 'dart:convert';

import 'package:agora_poc/features/call/data/token_server_client.dart';
import 'package:agora_poc/features/call/domain/token_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TokenServerClient clientWith(MockClientHandler handler, {int? expire}) =>
      TokenServerClient(
        baseUrl: Uri.parse('http://127.0.0.1:8080'),
        httpClient: MockClient(handler),
        expireSeconds: expire,
      );

  test('asks for channel, uid and expiry, and returns the token', () async {
    late Uri requested;
    final client = clientWith((request) async {
      requested = request.url;
      return http.Response(jsonEncode({'token': '007abc'}), 200);
    }, expire: 120);

    final token = await client.rtcToken(channelId: 'room 1', uid: 42);

    expect(token, '007abc');
    expect(requested.path, '/rtc-token');
    expect(requested.queryParameters, {
      'channel': 'room 1',
      'uid': '42',
      'expire': '120',
    });
  });

  test('server errors carry the server\'s message', () async {
    final client = clientWith(
      (_) async => http.Response(jsonEncode({'error': 'bad channel'}), 400),
    );

    expect(
      () => client.rtcToken(channelId: 'x', uid: 1),
      throwsA(
        isA<TokenUnavailableException>().having(
          (e) => e.message,
          'message',
          contains('bad channel'),
        ),
      ),
    );
  });

  test('unreachable server and non-JSON replies are clear errors', () async {
    final down = clientWith((_) async => throw http.ClientException('refused'));
    final html = clientWith((_) async => http.Response('<html>', 502));
    final empty = clientWith((_) async => http.Response('{}', 200));

    for (final client in [down, html, empty]) {
      await expectLater(
        client.rtcToken(channelId: 'x', uid: 1),
        throwsA(isA<TokenUnavailableException>()),
      );
    }
  });
}
