import 'package:agora_poc/core/config/agora_config.dart';
import 'package:agora_poc/features/call/data/token_server_client.dart';
import 'package:agora_poc/features/call/domain/saved_token_store.dart';
import 'package:agora_poc/features/call/presentation/providers/call_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class InMemoryTokenStore implements SavedTokenStore {
  String? value;

  @override
  String? read() => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> clear() async => value = null;
}

void main() {
  late InMemoryTokenStore store;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryTokenStore();
    container = ProviderContainer.test(
      overrides: [
        agoraConfigProvider.overrideWithValue(
          const AgoraConfig(
            appId: 'app',
            defaultChannelId: 'room',
            staticToken: 'built-in',
          ),
        ),
        savedTokenStoreProvider.overrideWithValue(store),
      ],
    );
  });

  String token() => container.read(manualTokenControllerProvider);

  test('uses the built-in token until one is pasted', () {
    expect(token(), 'built-in');
  });

  test('a pasted token is cleaned, saved and used', () async {
    await container
        .read(manualTokenControllerProvider.notifier)
        .save('  007abc\n def ');

    expect(token(), '007abcdef');
    expect(store.value, '007abcdef');
  });

  test('a saved token survives an app restart', () {
    store.value = '007saved';
    expect(token(), '007saved');
  });

  test('reset goes back to the built-in token', () async {
    store.value = '007saved';
    await container
        .read(manualTokenControllerProvider.notifier)
        .resetToBuiltIn();

    expect(token(), 'built-in');
    expect(store.value, isNull);
  });

  test('calls pick up a newly pasted token without a rebuild', () async {
    final provider = container.read(tokenProviderProvider);
    expect(provider, isA<StaticTokenProvider>());

    await container.read(manualTokenControllerProvider.notifier).save('007new');

    expect(await provider.rtcToken(channelId: 'room', uid: 1), '007new');
    expect(container.read(tokenProviderProvider), same(provider));
  });
}
