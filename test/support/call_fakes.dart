import 'dart:async';
import 'dart:typed_data';

import 'package:agora_poc/core/config/agora_config.dart';
import 'package:agora_poc/features/call/domain/call_engine.dart';
import 'package:agora_poc/features/call/domain/call_keep_alive.dart';
import 'package:agora_poc/features/call/domain/call_message.dart';
import 'package:agora_poc/features/call/domain/call_permissions.dart';
import 'package:agora_poc/features/call/domain/call_session.dart';
import 'package:agora_poc/features/call/domain/pip_service.dart';
import 'package:agora_poc/features/call/domain/token_provider.dart';
import 'package:agora_poc/features/call/presentation/providers/call_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// One fake standing in for every engine-facing interface, recording calls.
class FakeEngine
    implements CallEngine, MediaEffects, CallCapture, PreCallTests {
  final _events = StreamController<CallEvent>.broadcast();
  final calls = <String>[];
  Object? joinError;
  bool screenShareSupported = true;

  void emit(CallEvent event) => _events.add(event);

  void emitMessage(int fromUid, CallMessage message) => emit(
    DataMessageReceived(
      fromUid: fromUid,
      bytes: CallMessageCodec.encode(message),
    ),
  );

  Future<void> _record(String call) async => calls.add(call);

  @override
  Stream<CallEvent> get events => _events.stream;

  @override
  Future<void> initialize({required String appId}) => _record('init:$appId');
  @override
  Future<void> startPreview() => _record('startPreview');
  @override
  Future<void> stopPreview() => _record('stopPreview');
  @override
  Future<void> join({
    required String channelId,
    required String token,
    required int uid,
  }) async {
    calls.add('join:$channelId:$uid:$token');
    final error = joinError;
    if (error != null) throw error;
  }

  @override
  Future<void> leave() => _record('leave');
  @override
  Future<void> renewToken(String token) => _record('renew:$token');
  @override
  Future<void> setMicMuted(bool muted) => _record('mic:$muted');
  @override
  Future<void> setCameraEnabled(bool enabled) => _record('camera:$enabled');
  @override
  Future<void> switchCamera() => _record('switchCamera');
  @override
  Future<void> setSpeakerOn(bool speakerOn) => _record('speaker:$speakerOn');
  @override
  Future<void> setOthersMuted(bool muted) => _record('othersMuted:$muted');
  @override
  Future<void> setRemoteVideoHighQuality({
    required int uid,
    required bool high,
  }) => _record('quality:$uid:${high ? 'high' : 'low'}');
  @override
  Future<void> dispose() => _events.close();

  // MediaEffects
  @override
  Future<bool> isBackgroundBlurSupported() async => true;
  @override
  Future<void> setVideoQuality(VideoQuality quality) =>
      _record('videoQuality:${quality.name}');
  @override
  Future<void> setNoiseSuppression(bool enabled) => _record('ains:$enabled');
  @override
  Future<void> setBackgroundBlur(bool enabled) => _record('blur:$enabled');
  @override
  Future<void> setBeauty(bool enabled) => _record('beauty:$enabled');
  @override
  Future<void> setAudioOnly(bool enabled) => _record('audioOnly:$enabled');
  @override
  Future<void> setEncryption({
    required String passphrase,
    required String channelId,
  }) => _record('encryption:${passphrase.isNotEmpty}');

  // CallCapture
  @override
  bool get isScreenShareSupported => screenShareSupported;
  @override
  Future<void> startScreenShare({
    required String channelId,
    required int shareUid,
    required String token,
  }) => _record('screenStart:$shareUid');
  @override
  Future<void> stopScreenShare() => _record('screenStop');
  @override
  Future<void> renewScreenShareToken(String token) =>
      _record('screenRenew:$token');
  @override
  Future<void> takeSnapshot({required int uid, required String filePath}) =>
      _record('snapshot:$uid');
  @override
  Future<void> startRecording({
    required String channelId,
    required int uid,
    required String filePath,
  }) => _record('recordStart:$uid');
  @override
  Future<void> stopRecording() => _record('recordStop');

  // PreCallTests
  @override
  Future<void> startEchoTest({
    required String channelId,
    required String token,
    required int delaySeconds,
  }) => _record('echoStart');
  @override
  Future<void> stopEchoTest() => _record('echoStop');
  @override
  Future<void> startNetworkTest() => _record('networkStart');
  @override
  Future<void> stopNetworkTest() => _record('networkStop');
}

class FakeMessaging implements CallMessaging {
  final sent = <CallMessage>[];

  @override
  Future<void> send(Uint8List bytes) async {
    final message = CallMessageCodec.decode(bytes);
    if (message != null) sent.add(message);
  }
}

class FakePip implements PipService {
  final _status = StreamController<PipStatus>.broadcast();
  final calls = <String>[];
  bool isSupported = true;
  List<int>? lastRemoteUids;
  bool? lastAutoEnterAllowed;

  void emit(PipStatus status) => _status.add(status);

  @override
  Stream<PipStatus> get statusChanges => _status.stream;
  @override
  Future<bool> prepare() async {
    calls.add('prepare');
    return isSupported;
  }

  @override
  Future<void> configure({
    required String channelId,
    required int localUid,
    required List<int> remoteUids,
    required bool isAutoEnterAllowed,
  }) async {
    calls.add('configure');
    lastRemoteUids = remoteUids;
    lastAutoEnterAllowed = isAutoEnterAllowed;
  }

  @override
  Future<void> enterOnBackground() async => calls.add('enter');
  @override
  Future<void> exitOnForeground() async => calls.add('exit');
  @override
  Future<void> release() async => calls.add('release');
}

class FakePermissions implements CallPermissions {
  CallPermissionResult result = CallPermissionResult.granted;
  int requests = 0;

  /// What a check (without asking) returns, e.g. after a Settings change.
  bool isGrantedNow = false;

  @override
  Future<CallPermissionResult> requestCameraAndMic() async {
    requests++;
    return result;
  }

  @override
  Future<bool> hasCameraAndMic() async => isGrantedNow;
  @override
  Future<void> openSettings() async {}
}

class FakeKeepAlive implements CallKeepAlive {
  final calls = <String>[];

  @override
  Future<void> start({required String title, required String text}) async =>
      calls.add('start');

  @override
  Future<void> stop() async => calls.add('stop');
}

class FakeTokens implements TokenProvider {
  final requests = <String>[];
  Object? error;
  int _counter = 0;

  /// When set, token requests wait for it, to test cancelling mid-join.
  Completer<void>? hold;

  @override
  Future<String> rtcToken({required String channelId, required int uid}) async {
    requests.add('$channelId:$uid');
    await hold?.future;
    final failure = error;
    if (failure != null) throw failure;
    return 'token-${++_counter}';
  }
}

const testConfig = AgoraConfig(
  appId: 'app-id',
  defaultChannelId: 'room',
  tokenServerUrl: 'http://127.0.0.1:8080',
);

/// Short so tests can wait past it in real time.
const frozenNoticeDelay = Duration(milliseconds: 40);
const noVideoTimeout = Duration(milliseconds: 40);
const slowJoinNoticeDelay = Duration(milliseconds: 40);
const presenceHeartbeat = Duration(milliseconds: 40);
const presenceFollowUp = Duration(milliseconds: 60);

const myUid = 111;
const myShareUid = 222;

CallSession testSession({
  ParticipantRole role = ParticipantRole.guest,
  bool startWithMic = true,
  String passphrase = '',
}) => CallSession(
  channelId: 'room',
  localUid: myUid,
  screenShareUid: myShareUid,
  displayName: 'Me',
  role: role,
  startWithMic: startWithMic,
  startWithCamera: true,
  encryptionPassphrase: passphrase,
);

class CallTestHarness {
  CallTestHarness({Duration heartbeat = presenceHeartbeat}) {
    container = ProviderContainer.test(
      overrides: [
        agoraConfigProvider.overrideWithValue(testConfig),
        callEngineProvider.overrideWithValue(engine),
        mediaEffectsProvider.overrideWithValue(engine),
        callCaptureProvider.overrideWithValue(engine),
        preCallTestsProvider.overrideWithValue(engine),
        callMessagingProvider.overrideWithValue(messaging),
        pipServiceProvider.overrideWithValue(pip),
        callPermissionsProvider.overrideWithValue(permissions),
        tokenProviderProvider.overrideWithValue(tokens),
        uidGeneratorProvider.overrideWithValue(_nextUid),
        frozenNoticeDelayProvider.overrideWithValue(frozenNoticeDelay),
        noVideoTimeoutProvider.overrideWithValue(noVideoTimeout),
        slowJoinNoticeDelayProvider.overrideWithValue(slowJoinNoticeDelay),
        presenceHeartbeatProvider.overrideWithValue(heartbeat),
        presenceFollowUpProvider.overrideWithValue(presenceFollowUp),
        callKeepAliveProvider.overrideWithValue(keepAliveService),
      ],
    );
  }

  final engine = FakeEngine();
  final messaging = FakeMessaging();
  final pip = FakePip();
  final permissions = FakePermissions();
  final tokens = FakeTokens();
  final keepAliveService = FakeKeepAlive();
  late final ProviderContainer container;
  final _uids = [myUid, myShareUid];

  int _nextUid() => _uids.isEmpty ? 999 : _uids.removeAt(0);

  /// Keeps an auto-created controller alive and listening for the test.
  void keepAlive<T>(ProviderListenable<T> provider) =>
      container.listen(provider, (_, _) {});
}

/// Lets broadcast-stream events and unawaited futures settle.
Future<void> settle() => Future<void>.delayed(Duration.zero);
