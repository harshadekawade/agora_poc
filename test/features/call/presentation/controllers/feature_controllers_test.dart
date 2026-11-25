import 'package:agora_poc/features/call/domain/call_engine.dart';
import 'package:agora_poc/features/call/domain/call_message.dart';
import 'package:agora_poc/features/call/domain/call_metrics.dart';
import 'package:agora_poc/features/call/domain/call_permissions.dart';
import 'package:agora_poc/features/call/presentation/providers/call_providers.dart';
import 'package:agora_poc/features/call/presentation/state/pre_call_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/call_fakes.dart';

void main() {
  late CallTestHarness h;

  setUp(() => h = CallTestHarness());

  group('SpeakingController', () {
    test('local and remote reports merge; silent remotes drop out', () async {
      h.keepAlive(speakingControllerProvider);
      h.engine
        ..emit(const VolumesUpdated({0: 80}))
        ..emit(const VolumesUpdated({5: 120, 6: 40}));
      await settle();
      expect(h.container.read(speakingControllerProvider), {
        0: 80,
        5: 120,
        6: 40,
      });

      h.engine.emit(const VolumesUpdated({6: 90}));
      await settle();
      expect(h.container.read(speakingControllerProvider), {0: 80, 6: 90});
    });
  });

  group('ChatController', () {
    test(
      'sends ours, receives theirs and counts unread while closed',
      () async {
        h.keepAlive(chatControllerProvider);
        final chat = h.container.read(chatControllerProvider.notifier);

        await chat.send('  hello  ');
        h.engine.emitMessage(5, const ChatMessageSent('hi back'));
        await settle();

        final state = h.container.read(chatControllerProvider);
        expect(state.entries.map((e) => (e.text, e.isMine)), [
          ('hello', true),
          ('hi back', false),
        ]);
        expect(state.unreadCount, 1);
        expect(h.messaging.sent.single, isA<ChatMessageSent>());

        chat.setOpen(true);
        expect(h.container.read(chatControllerProvider).unreadCount, 0);
      },
    );

    test('blank messages are not sent', () async {
      h.keepAlive(chatControllerProvider);
      await h.container.read(chatControllerProvider.notifier).send('   ');
      expect(h.messaging.sent, isEmpty);
    });
  });

  group('MediaSettingsController', () {
    test('choices before the engine starts are applied by applyAll', () async {
      h.keepAlive(mediaSettingsControllerProvider);
      final media = h.container.read(mediaSettingsControllerProvider.notifier);

      await media.toggleNoiseSuppression();
      await media.setQuality(VideoQuality.hd);
      expect(h.engine.calls, isEmpty);

      await media.applyAll();
      expect(h.engine.calls, containsAll(['videoQuality:hd', 'ains:true']));
    });

    test('after the engine starts, changes apply immediately', () async {
      h.keepAlive(mediaSettingsControllerProvider);
      final media = h.container.read(mediaSettingsControllerProvider.notifier);
      await media.applyAll();

      await media.toggleAudioOnly();
      expect(h.engine.calls.last, 'audioOnly:true');
      expect(
        h.container.read(mediaSettingsControllerProvider).isAudioOnly,
        isTrue,
      );
    });
  });

  group('PreCallController', () {
    test('allowed in Settings while away: starts again on return', () async {
      h.permissions.result = CallPermissionResult.permanentlyDenied;
      h.keepAlive(preCallControllerProvider);
      final pre = h.container.read(preCallControllerProvider.notifier);
      await pre.prepare();
      expect(
        h.container.read(preCallControllerProvider).failure,
        PreCallFailure.permissionPermanentlyDenied,
      );

      h.permissions
        ..result = CallPermissionResult.granted
        ..isGrantedNow = true;
      await pre.recheckPermissions();

      expect(h.container.read(preCallControllerProvider).isReady, isTrue);
    });

    test('still blocked on return: no new permission prompt', () async {
      h.permissions.result = CallPermissionResult.denied;
      h.keepAlive(preCallControllerProvider);
      final pre = h.container.read(preCallControllerProvider.notifier);
      await pre.prepare();
      final asked = h.permissions.requests;

      await pre.recheckPermissions();

      expect(h.permissions.requests, asked);
      expect(
        h.container.read(preCallControllerProvider).failure,
        PreCallFailure.permissionDenied,
      );
    });

    test('returning when nothing was blocked does nothing', () async {
      h.keepAlive(preCallControllerProvider);
      final pre = h.container.read(preCallControllerProvider.notifier);
      await pre.prepare();
      h.permissions.isGrantedNow = true;
      final calls = [...h.engine.calls];

      await pre.recheckPermissions();

      expect(h.engine.calls, calls);
    });

    test('denied permission stops before the engine starts', () async {
      h.permissions.result = CallPermissionResult.denied;
      h.keepAlive(preCallControllerProvider);

      await h.container.read(preCallControllerProvider.notifier).prepare();

      final state = h.container.read(preCallControllerProvider);
      expect(state.failure, PreCallFailure.permissionDenied);
      expect(h.engine.calls, isEmpty);
    });

    test('prepare starts the engine and preview', () async {
      h.keepAlive(preCallControllerProvider);
      await h.container.read(preCallControllerProvider.notifier).prepare();

      expect(h.container.read(preCallControllerProvider).isReady, isTrue);
      expect(
        h.engine.calls,
        containsAllInOrder(['init:app-id', 'startPreview']),
      );
    });

    test('during a call it never touches the shared camera', () async {
      h.keepAlive(preCallControllerProvider);
      h.keepAlive(callControllerProvider);
      final pre = h.container.read(preCallControllerProvider.notifier);
      await pre.prepare();
      await h.container
          .read(callControllerProvider.notifier)
          .join(testSession());
      h.engine.calls.clear();

      await pre.prepare();
      await pre.toggleStartWithCamera();
      await pre.cancel();

      expect(h.engine.calls, isEmpty);
    });

    test('encryption on with no passphrase blocks joining', () async {
      h.keepAlive(preCallControllerProvider);
      final pre = h.container.read(preCallControllerProvider.notifier);
      await pre.prepare();

      pre.toggleEncryption();
      expect(h.container.read(preCallControllerProvider).canJoin, isFalse);
      expect(await pre.finish(), isNull);

      pre.setEncryptionPassphrase('secret');
      final session = await pre.finish();
      expect(session?.encryptionPassphrase, 'secret');
      expect(session?.localUid, myUid);
      expect(session?.screenShareUid, myShareUid);
    });

    test('network test result is captured and the test stopped', () async {
      h.keepAlive(preCallControllerProvider);
      final pre = h.container.read(preCallControllerProvider.notifier);
      await pre.prepare();
      await pre.toggleNetworkTest();

      h.engine.emit(
        const NetworkTestCompleted(
          NetworkTestResult(
            isComplete: true,
            roundTripMs: 40,
            uplinkKbps: 2000,
            uplinkLossPercent: 0,
            uplinkJitterMs: 3,
            downlinkKbps: 5000,
            downlinkLossPercent: 1,
            downlinkJitterMs: 4,
          ),
        ),
      );
      await settle();

      final state = h.container.read(preCallControllerProvider);
      expect(state.networkResult?.downlinkKbps, 5000);
      expect(state.networkStatus, NetworkTestStatus.done);
      expect(h.engine.calls, contains('networkStop'));
    });

    test('echo test asks the server for a token, then runs', () async {
      h.keepAlive(preCallControllerProvider);
      final pre = h.container.read(preCallControllerProvider.notifier);
      await pre.prepare();
      await pre.toggleEchoTest();

      expect(h.tokens.requests.single, 'echo-$myUid:0');
      expect(
        h.container.read(preCallControllerProvider).echoStatus,
        EchoTestStatus.running,
      );
      await pre.toggleEchoTest();
      expect(h.engine.calls, contains('echoStop'));
    });
  });
}
