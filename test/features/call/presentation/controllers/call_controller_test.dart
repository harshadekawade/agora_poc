import 'dart:async';

import 'package:agora_poc/features/call/domain/call_engine.dart';
import 'package:agora_poc/features/call/domain/call_message.dart';
import 'package:agora_poc/features/call/domain/call_session.dart';
import 'package:agora_poc/features/call/domain/pip_service.dart';
import 'package:agora_poc/features/call/domain/token_provider.dart';
import 'package:agora_poc/features/call/presentation/providers/call_providers.dart';
import 'package:agora_poc/features/call/presentation/state/call_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/call_fakes.dart';

void main() {
  late CallTestHarness h;

  CallState state() => h.container.read(callControllerProvider);

  Future<void> joinCall({CallSession? session}) async {
    h.keepAlive(callControllerProvider);
    await h.container
        .read(callControllerProvider.notifier)
        .join(session ?? testSession());
    h.engine.emit(const CallJoined(localUid: myUid, elapsedMs: 100));
    await settle();
  }

  setUp(() => h = CallTestHarness());

  group('join', () {
    test('fetches a token for our uid, then joins with it', () async {
      await joinCall();

      expect(h.tokens.requests, ['room:$myUid']);
      expect(h.engine.calls, contains('join:room:$myUid:token-1'));
      expect(state().status, CallStatus.inCall);
      expect(state().joinedAt, isNotNull);
    });

    test('applies encryption and start-muted before joining', () async {
      await joinCall(
        session: testSession(startWithMic: false, passphrase: 'x'),
      );

      final joinIndex = h.engine.calls.indexWhere((c) => c.startsWith('join'));
      expect(h.engine.calls.indexOf('encryption:true'), lessThan(joinIndex));
      expect(h.engine.calls.indexOf('mic:true'), lessThan(joinIndex));
      expect(state().isMicMuted, isTrue);
    });

    test('announces who we are once joined', () async {
      await joinCall(session: testSession(role: ParticipantRole.host));

      final presence = h.messaging.sent.whereType<PresenceMessage>().single;
      expect(presence.name, 'Me');
      expect(presence.role, ParticipantRole.host);
    });

    test('token server failure fails the call without joining', () async {
      h.tokens.error = const TokenUnavailableException('server down');
      h.keepAlive(callControllerProvider);

      await h.container
          .read(callControllerProvider.notifier)
          .join(testSession());

      expect(state().failure, CallFailure.tokenUnavailable);
      expect(state().failureDetail, 'server down');
      expect(h.engine.calls.where((c) => c.startsWith('join')), isEmpty);
    });

    test('leaving while the token loads never joins', () async {
      h.tokens.hold = Completer<void>();
      h.keepAlive(callControllerProvider);
      final controller = h.container.read(callControllerProvider.notifier);

      final joining = controller.join(testSession());
      await settle();
      await controller.leave();
      h.tokens.hold!.complete();
      await joining;

      expect(h.engine.calls.where((c) => c.startsWith('join')), isEmpty);
      expect(state().status, CallStatus.ended);
    });

    test('a join that succeeds after cancelling is left again', () async {
      h.keepAlive(callControllerProvider);
      final controller = h.container.read(callControllerProvider.notifier);
      await controller.join(testSession());
      await controller.leave();
      h.engine.calls.clear();

      h.engine.emit(const CallJoined(localUid: myUid, elapsedMs: 100));
      await settle();

      expect(state().status, CallStatus.ended);
      expect(h.engine.calls, contains('leave'));
    });

    test('a second join while busy is ignored', () async {
      await joinCall();
      await h.container
          .read(callControllerProvider.notifier)
          .join(testSession());

      expect(h.engine.calls.where((c) => c.startsWith('join')), hasLength(1));
    });
  });

  group('participants', () {
    test('presence names people; leaving removes them', () async {
      await joinCall();

      h.engine.emit(const RemoteUserJoined(5));
      h.engine.emitMessage(
        5,
        const PresenceMessage(
          name: 'Dr Rao',
          role: ParticipantRole.host,
          isHandRaised: false,
        ),
      );
      await settle();
      expect(state().participants[5]?.name, 'Dr Rao');
      expect(state().participants[5]?.role, ParticipantRole.host);

      h.engine.emit(const RemoteUserLeft(uid: 5, reason: 'quit'));
      await settle();
      expect(state().participants, isEmpty);
    });

    test('mic and video changes update the participant', () async {
      await joinCall();
      h.engine
        ..emit(const RemoteUserJoined(5))
        ..emit(const RemoteAudioMuted(uid: 5, muted: true))
        ..emit(
          const RemoteVideoChanged(uid: 5, status: RemoteVideoStatus.frozen),
        );
      await settle();

      expect(state().participants[5]?.isMicOn, isFalse);
      expect(state().participants[5]?.videoStatus, RemoteVideoStatus.frozen);
    });

    test('a presence with a screen uid marks that uid as a screen', () async {
      await joinCall();
      h.engine
        ..emit(const RemoteUserJoined(5))
        ..emit(const RemoteUserJoined(6))
        ..emitMessage(
          5,
          const PresenceMessage(
            name: 'Dr Rao',
            role: ParticipantRole.host,
            isHandRaised: false,
            screenShareUid: 6,
          ),
        );
      await settle();

      expect(state().screenShareOwners, {6: 5});
      expect(state().people.map((p) => p.uid), [5]);
    });

    test('small 1:1 tiles get full quality, a crowded grid gets low', () async {
      await joinCall();
      h.engine.emit(const RemoteUserJoined(5));
      await settle();
      expect(h.engine.calls, contains('quality:5:high'));

      h.engine
        ..emit(const RemoteUserJoined(6))
        ..emit(const RemoteUserJoined(7));
      await settle();
      expect(h.engine.calls, contains('quality:5:low'));
    });
  });

  group('host actions', () {
    Future<void> addHost(int uid) async {
      h.engine
        ..emit(RemoteUserJoined(uid))
        ..emitMessage(
          uid,
          const PresenceMessage(
            name: 'Host',
            role: ParticipantRole.host,
            isHandRaised: false,
          ),
        );
      await settle();
    }

    test('a host mute request prompts us; accepting mutes', () async {
      await joinCall();
      await addHost(5);

      h.engine.emitMessage(5, const MuteRequestMessage(targetUid: myUid));
      await settle();
      expect(state().pendingMuteRequestFromUid, 5);

      await h.container
          .read(callControllerProvider.notifier)
          .acceptMuteRequest();
      expect(state().isMicMuted, isTrue);
      expect(state().pendingMuteRequestFromUid, isNull);
    });

    test('mute requests from non-hosts are ignored', () async {
      await joinCall();
      h.engine
        ..emit(const RemoteUserJoined(9))
        ..emitMessage(9, const MuteRequestMessage(targetUid: myUid));
      await settle();

      expect(state().pendingMuteRequestFromUid, isNull);
    });

    test('a host remove request ends our call', () async {
      await joinCall();
      await addHost(5);

      h.engine.emitMessage(5, const RemoveRequestMessage(targetUid: myUid));
      await settle();

      expect(state().failure, CallFailure.removedByHost);
      expect(h.engine.calls, contains('leave'));
    });

    test('only hosts can send host actions', () async {
      await joinCall();
      await h.container.read(callControllerProvider.notifier).requestMute(5);
      expect(h.messaging.sent.whereType<MuteRequestMessage>(), isEmpty);
    });
  });

  group('connection and tokens', () {
    test('reconnecting then connected returns to in call', () async {
      await joinCall();
      h.engine.emit(
        const ConnectionChanged(
          state: CallConnectionState.reconnecting,
          reason: 'lost',
        ),
      );
      await settle();
      expect(state().status, CallStatus.reconnecting);

      h.engine.emit(
        const ConnectionChanged(
          state: CallConnectionState.connected,
          reason: 'ok',
        ),
      );
      await settle();
      expect(state().status, CallStatus.inCall);
    });

    test(
      'a rejected token fails with a plain message, no vendor code',
      () async {
        h.keepAlive(callControllerProvider);
        await h.container
            .read(callControllerProvider.notifier)
            .join(testSession());
        h.engine.emit(
          const ConnectionChanged(
            state: CallConnectionState.failed,
            reason: 'connectionChangedInvalidToken',
            isTokenRejected: true,
          ),
        );
        await settle();

        expect(state().failure, CallFailure.tokenRejected);
        expect(state().failureDetail, isNull);
      },
    );

    test('other connection failures say so without a vendor code', () async {
      await joinCall();
      h.engine.emit(
        const ConnectionChanged(
          state: CallConnectionState.failed,
          reason: 'connectionChangedBannedByServer',
        ),
      );
      await settle();

      expect(state().failure, CallFailure.connectionFailed);
      expect(state().failureDetail, isNull);
    });

    test('expiring call token is renewed with a fresh one', () async {
      await joinCall();
      h.engine.emit(const TokenWillExpire(localUid: myUid));
      await settle();

      expect(h.engine.calls, contains('renew:token-2'));
      expect(state().isTokenExpiring, isFalse);
    });

    test('expiring screen token renews the screen connection', () async {
      await joinCall();
      h.engine.emit(const TokenWillExpire(localUid: myShareUid));
      await settle();

      expect(h.tokens.requests.last, 'room:$myShareUid');
      expect(h.engine.calls, contains('screenRenew:token-2'));
    });

    test('expired token that cannot be renewed fails the call', () async {
      await joinCall();
      h.tokens.error = const TokenUnavailableException('down');
      h.engine.emit(const TokenExpired(localUid: myUid));
      await settle();

      expect(state().failure, CallFailure.tokenExpired);
    });
  });

  group('screen share', () {
    test('start fetches a token for the screen uid', () async {
      await joinCall();
      await h.container
          .read(callControllerProvider.notifier)
          .toggleScreenShare();

      expect(h.tokens.requests.last, 'room:$myShareUid');
      expect(h.engine.calls, contains('screenStart:$myShareUid'));
    });

    test('becoming active re-announces presence with the screen uid', () async {
      await joinCall();
      h.engine.emit(
        const ScreenShareStateChanged(status: ScreenShareStatus.active),
      );
      await settle();

      expect(state().isScreenSharing, isTrue);
      expect(
        h.messaging.sent.whereType<PresenceMessage>().last.screenShareUid,
        myShareUid,
      );
    });

    test('no auto-PiP while asking to share; allowed once sharing', () async {
      await joinCall();
      final controller = h.container.read(callControllerProvider.notifier);
      await controller.toggleScreenShare();
      expect(h.pip.lastAutoEnterAllowed, isFalse);

      // The permission dialog makes the app inactive: no PiP for that.
      h.pip.calls.clear();
      await controller.onAppLifecycleChanged(AppLifecycleState.inactive);
      expect(h.pip.calls, isNot(contains('enter')));

      h.engine.emit(
        const ScreenShareStateChanged(status: ScreenShareStatus.active),
      );
      await settle();
      expect(h.pip.lastAutoEnterAllowed, isTrue);

      // Sharing: leaving the app goes to PiP again.
      h.pip.calls.clear();
      await controller.onAppLifecycleChanged(AppLifecycleState.inactive);
      expect(h.pip.calls, contains('enter'));
    });

    test('a share that fails before starting is cleaned up', () async {
      await joinCall();
      await h.container
          .read(callControllerProvider.notifier)
          .toggleScreenShare();
      h.engine.calls.clear();

      h.engine.emit(
        const ScreenShareStateChanged(status: ScreenShareStatus.failed),
      );
      await settle();

      expect(h.engine.calls, contains('screenStop'));
      expect(h.pip.lastAutoEnterAllowed, isTrue);
    });

    test('leaving always clears a half-started share', () async {
      await joinCall();
      final controller = h.container.read(callControllerProvider.notifier);
      await controller.toggleScreenShare();
      await controller.leave();

      expect(h.engine.calls, contains('screenStop'));
    });

    test('unsupported platforms never start sharing', () async {
      h.engine.screenShareSupported = false;
      await joinCall();
      await h.container
          .read(callControllerProvider.notifier)
          .toggleScreenShare();

      expect(h.engine.calls, isNot(contains('screenStart:$myShareUid')));
    });
  });

  group('controls, layout and PiP', () {
    test('mic, camera and earpiece go through the engine', () async {
      await joinCall();
      final controller = h.container.read(callControllerProvider.notifier);
      await controller.toggleMic();
      await controller.toggleCamera();
      await controller.setAudioOutput(CallAudioOutput.earpiece);

      expect(state().isMicMuted, isTrue);
      expect(state().isCameraOn, isFalse);
      expect(h.engine.calls, contains('speaker:false'));
      expect(state().audioOutput, CallAudioOutput.earpiece);
    });

    test(
      'sound off mutes everyone; picking a route turns it back on',
      () async {
        await joinCall();
        final controller = h.container.read(callControllerProvider.notifier);

        await controller.setAudioOutput(CallAudioOutput.off);
        expect(h.engine.calls.last, 'othersMuted:true');
        expect(state().audioOutput, CallAudioOutput.off);

        await controller.setAudioOutput(CallAudioOutput.speaker);
        expect(h.engine.calls.last, 'othersMuted:false');
        expect(state().audioOutput, CallAudioOutput.speaker);
      },
    );

    test('a new call always starts with sound on', () async {
      await joinCall();

      final joinIndex = h.engine.calls.indexWhere((c) => c.startsWith('join'));
      expect(h.engine.calls.indexOf('othersMuted:false'), lessThan(joinIndex));
    });

    test('pinning switches to speaker view; unpinning clears it', () async {
      await joinCall();
      h.engine.emit(const RemoteUserJoined(5));
      await settle();
      final controller = h.container.read(callControllerProvider.notifier);

      controller.togglePin(5);
      expect(state().pinnedUid, 5);
      expect(state().layout, CallLayout.speaker);

      controller.togglePin(5);
      expect(state().pinnedUid, isNull);
    });

    test('app going inactive enters PiP, resuming exits', () async {
      await joinCall();
      final controller = h.container.read(callControllerProvider.notifier);
      await controller.onAppLifecycleChanged(AppLifecycleState.inactive);
      await controller.onAppLifecycleChanged(AppLifecycleState.resumed);

      expect(h.pip.calls, containsAllInOrder(['prepare', 'enter', 'exit']));
    });

    test('PiP status is reflected in state', () async {
      await joinCall();
      h.pip.emit(PipStatus.active);
      await settle();
      expect(state().isPipActive, isTrue);
    });

    test('closing the PiP window leaves the call', () async {
      await joinCall();
      final controller = h.container.read(callControllerProvider.notifier);
      h.pip.emit(PipStatus.active);
      await settle();
      h.pip.emit(PipStatus.inactive);
      await settle();
      await controller.onAppLifecycleChanged(AppLifecycleState.paused);
      await settle();

      expect(state().status, CallStatus.ended);
      expect(h.engine.calls, contains('leave'));
    });

    test('closing PiP leaves even if the stop arrives first', () async {
      await joinCall();
      final controller = h.container.read(callControllerProvider.notifier);
      h.pip.emit(PipStatus.active);
      await settle();
      await controller.onAppLifecycleChanged(AppLifecycleState.paused);
      h.pip.emit(PipStatus.inactive);
      await settle();

      expect(state().status, CallStatus.ended);
    });

    test('expanding the PiP window keeps the call', () async {
      await joinCall();
      final controller = h.container.read(callControllerProvider.notifier);
      h.pip.emit(PipStatus.active);
      await settle();
      h.pip.emit(PipStatus.inactive);
      await settle();
      await controller.onAppLifecycleChanged(AppLifecycleState.resumed);
      await controller.onAppLifecycleChanged(AppLifecycleState.paused);

      expect(state().status, CallStatus.inCall);
    });

    test('leave ends the call and releases PiP', () async {
      await joinCall();
      await h.container.read(callControllerProvider.notifier).leave();

      expect(state().status, CallStatus.ended);
      expect(h.engine.calls, contains('leave'));
      expect(h.pip.calls, contains('release'));
    });
  });

  group('video states and layout for screen shares', () {
    Future<void> addSharer({required int owner, required int screen}) async {
      h.engine
        ..emit(RemoteUserJoined(owner))
        ..emit(RemoteUserJoined(screen))
        ..emitMessage(
          owner,
          PresenceMessage(
            name: 'Sharer',
            role: ParticipantRole.guest,
            isHandRaised: false,
            screenShareUid: screen,
          ),
        );
      await settle();
    }

    test('a new participant is connecting until their first frame', () async {
      await joinCall();
      h.engine.emit(const RemoteUserJoined(5));
      await settle();
      expect(
        state().participants[5]?.videoStatus,
        RemoteVideoStatus.connecting,
      );

      h.engine.emit(
        const RemoteVideoChanged(uid: 5, status: RemoteVideoStatus.on),
      );
      await settle();
      expect(state().participants[5]?.videoStatus, RemoteVideoStatus.on);
    });

    test('someone who never sends video is shown as camera off', () async {
      await joinCall();
      h.engine.emit(const RemoteUserJoined(5));
      await Future<void>.delayed(noVideoTimeout * 2);

      expect(state().participants[5]?.videoStatus, RemoteVideoStatus.off);
    });

    test('video arriving after the timeout still shows', () async {
      await joinCall();
      h.engine.emit(const RemoteUserJoined(5));
      await Future<void>.delayed(noVideoTimeout * 2);

      h.engine.emit(
        const RemoteVideoChanged(uid: 5, status: RemoteVideoStatus.on),
      );
      await settle();
      expect(state().participants[5]?.videoStatus, RemoteVideoStatus.on);
    });

    test('a slow start keeps connecting past the timeout', () async {
      await joinCall();
      h.engine
        ..emit(const RemoteUserJoined(5))
        ..emit(
          const RemoteVideoChanged(
            uid: 5,
            status: RemoteVideoStatus.connecting,
          ),
        );
      await Future<void>.delayed(noVideoTimeout * 2);

      expect(
        state().participants[5]?.videoStatus,
        RemoteVideoStatus.connecting,
      );
    });

    test('a short camera freeze never shows the notice', () async {
      await joinCall();
      h.engine
        ..emit(const RemoteUserJoined(5))
        ..emit(
          const RemoteVideoChanged(uid: 5, status: RemoteVideoStatus.frozen),
        )
        ..emit(const RemoteVideoChanged(uid: 5, status: RemoteVideoStatus.on));
      await Future<void>.delayed(frozenNoticeDelay * 2);

      expect(state().participants[5]?.isFrozenNoticeVisible, isFalse);
      expect(
        h.container
            .read(callLogProvider)
            .any((e) => e.message.contains('was frozen for')),
        isTrue,
      );
    });

    test('a camera frozen past the delay shows the notice', () async {
      await joinCall();
      h.engine
        ..emit(const RemoteUserJoined(5))
        ..emit(
          const RemoteVideoChanged(uid: 5, status: RemoteVideoStatus.frozen),
        );
      await settle();
      expect(state().participants[5]?.isFrozenNoticeVisible, isFalse);

      await Future<void>.delayed(frozenNoticeDelay * 2);
      expect(state().participants[5]?.isFrozenNoticeVisible, isTrue);

      h.engine.emit(
        const RemoteVideoChanged(uid: 5, status: RemoteVideoStatus.on),
      );
      await settle();
      expect(state().participants[5]?.isFrozenNoticeVisible, isFalse);
    });

    test('a still shared screen never shows the frozen notice', () async {
      await joinCall();
      await addSharer(owner: 5, screen: 6);
      h.engine.emit(
        const RemoteVideoChanged(uid: 6, status: RemoteVideoStatus.frozen),
      );
      await Future<void>.delayed(frozenNoticeDelay * 2);

      expect(state().participants[6]?.isFrozenNoticeVisible, isFalse);
    });

    test('someone sharing switches to speaker view, and back after', () async {
      await joinCall();
      await addSharer(owner: 5, screen: 6);
      expect(state().layout, CallLayout.speaker);

      h.engine.emitMessage(
        5,
        const PresenceMessage(
          name: 'Sharer',
          role: ParticipantRole.guest,
          isHandRaised: false,
        ),
      );
      await settle();
      expect(state().layout, CallLayout.grid);
    });

    test('a layout the user picked is not switched back', () async {
      await joinCall();
      await addSharer(owner: 5, screen: 6);
      final controller = h.container.read(callControllerProvider.notifier);
      controller
        ..setLayout(CallLayout.grid)
        ..setLayout(CallLayout.speaker);

      h.engine.emit(const RemoteUserLeft(uid: 6, reason: 'quit'));
      h.engine.emitMessage(
        5,
        const PresenceMessage(
          name: 'Sharer',
          role: ParticipantRole.guest,
          isHandRaised: false,
        ),
      );
      await settle();
      expect(state().layout, CallLayout.speaker);
    });

    test('our camera drops to Low while sharing, then is restored', () async {
      await joinCall();
      h.engine.emit(
        const ScreenShareStateChanged(status: ScreenShareStatus.active),
      );
      await settle();
      expect(h.engine.calls.last, 'videoQuality:low');

      h.engine.emit(
        const ScreenShareStateChanged(status: ScreenShareStatus.stopped),
      );
      await settle();
      expect(h.engine.calls.last, 'videoQuality:standard');
    });
  });

  group('background and slow joins', () {
    test('ongoing-call service runs only while the call is live', () async {
      await joinCall();
      expect(h.keepAliveService.calls, ['start']);

      // Reconnecting is still live: no restart.
      h.engine.emit(
        const ConnectionChanged(
          state: CallConnectionState.reconnecting,
          reason: 'test',
        ),
      );
      await settle();
      expect(h.keepAliveService.calls, ['start']);

      await h.container.read(callControllerProvider.notifier).leave();
      await settle();
      expect(h.keepAliveService.calls, ['start', 'stop']);
    });

    test('a failed call stops the ongoing-call service', () async {
      await joinCall();
      h.engine.emit(
        const ConnectionChanged(
          state: CallConnectionState.failed,
          reason: 'test',
        ),
      );
      await settle();

      expect(state().status, CallStatus.failed);
      expect(h.keepAliveService.calls, ['start', 'stop']);
    });

    test('a join that hangs says so, and joining clears it', () async {
      h.keepAlive(callControllerProvider);
      await h.container
          .read(callControllerProvider.notifier)
          .join(testSession());
      expect(state().isJoinSlow, isFalse);

      await Future<void>.delayed(slowJoinNoticeDelay * 2);
      expect(state().status, CallStatus.joining);
      expect(state().isJoinSlow, isTrue);
      expect(h.keepAliveService.calls, isEmpty);

      h.engine.emit(const CallJoined(localUid: myUid, elapsedMs: 100));
      await settle();
      expect(state().isJoinSlow, isFalse);
    });

    test('a quick join never shows the slow notice', () async {
      await joinCall();
      await Future<void>.delayed(slowJoinNoticeDelay * 2);

      expect(state().isJoinSlow, isFalse);
    });

    test('cancelling a slow join ends it', () async {
      h.keepAlive(callControllerProvider);
      final controller = h.container.read(callControllerProvider.notifier);
      await controller.join(testSession());
      await Future<void>.delayed(slowJoinNoticeDelay * 2);

      await controller.leave();

      expect(state().status, CallStatus.ended);
      expect(state().isJoinSlow, isFalse);
      expect(h.engine.calls, contains('leave'));
    });
  });

  group('presence is re-sent', () {
    int presenceCount() => h.messaging.sent.whereType<PresenceMessage>().length;

    test('repeatedly while live, and not after leaving', () async {
      await joinCall();
      final atJoin = presenceCount();

      await Future<void>.delayed(presenceHeartbeat * 3);
      expect(presenceCount(), greaterThan(atJoin));

      await h.container.read(callControllerProvider.notifier).leave();
      final atLeave = presenceCount();
      await Future<void>.delayed(presenceHeartbeat * 3);
      expect(presenceCount(), atLeave);
    });

    test('again shortly after someone joins', () async {
      h = CallTestHarness(heartbeat: const Duration(hours: 1));
      await joinCall();
      await Future<void>.delayed(presenceFollowUp * 2);
      final settled = presenceCount();

      h.engine.emit(const RemoteUserJoined(555));
      await Future<void>.delayed(const Duration(milliseconds: 450));

      // Once at ~400 ms and once more at the follow-up delay.
      expect(presenceCount(), settled + 2);
    });

    test('after a reconnect', () async {
      // No heartbeat during the test, so only the reconnect can re-send.
      h = CallTestHarness(heartbeat: const Duration(hours: 1));
      await joinCall();
      // Let the join's own announcements finish first.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      h.engine.emit(
        const ConnectionChanged(
          state: CallConnectionState.reconnecting,
          reason: 'test',
        ),
      );
      await settle();
      final beforeRejoin = presenceCount();

      h.engine.emit(
        const ConnectionChanged(
          state: CallConnectionState.connected,
          reason: 'test',
        ),
      );
      // The re-send is batched by a short delay (400 ms).
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(presenceCount(), greaterThan(beforeRejoin));
    });

    test('a host is recognised from a repeated announcement', () async {
      await joinCall();
      const doctor = 555;
      h.engine.emit(const RemoteUserJoined(doctor));
      await settle();
      // First announcement lost: the doctor's request is ignored.
      h.engine.emitMessage(doctor, const MuteRequestMessage(targetUid: myUid));
      await settle();
      expect(state().pendingMuteRequestFromUid, isNull);

      // A later heartbeat from the doctor arrives.
      h.engine.emitMessage(
        doctor,
        const PresenceMessage(
          name: 'Dr A',
          role: ParticipantRole.host,
          isHandRaised: false,
        ),
      );
      h.engine.emitMessage(doctor, const MuteRequestMessage(targetUid: myUid));
      await settle();

      expect(state().pendingMuteRequestFromUid, doctor);
    });
  });
}
