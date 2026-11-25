import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/agora_config.dart';
import '../../domain/call_engine.dart';
import '../../domain/call_permissions.dart';
import '../../domain/call_session.dart';
import '../../domain/token_provider.dart';
import '../providers/call_providers.dart';
import '../state/pre_call_state.dart';

/// The "green room": permissions, camera preview, mic/speaker and network
/// tests, and the choices made before joining.
class PreCallController extends Notifier<PreCallState> {
  /// Echo plays back what you said after this many seconds (Agora: 2–10).
  static const echoDelaySeconds = 3;

  /// Stop the echo test automatically so it can't run forever.
  static const _echoTestDuration = Duration(seconds: 15);

  /// The echo test needs a token; uid 0 tokens are valid for any uid.
  static const _echoTokenUid = 0;

  late CallEngine _engine;
  late PreCallTests _tests;
  late CallPermissions _permissions;
  late TokenProvider _tokens;
  late AgoraConfig _config;
  late int _localUid;
  late int _screenShareUid;
  Timer? _echoTimer;

  @override
  PreCallState build() {
    _engine = ref.watch(callEngineProvider);
    _tests = ref.watch(preCallTestsProvider);
    _permissions = ref.watch(callPermissionsProvider);
    _tokens = ref.watch(tokenProviderProvider);
    _config = ref.watch(agoraConfigProvider);
    final nextUid = ref.watch(uidGeneratorProvider);
    _localUid = nextUid();
    do {
      _screenShareUid = nextUid();
    } while (_screenShareUid == _localUid);

    final events = _engine.events.listen(_onEngineEvent);
    ref.onDispose(() {
      events.cancel();
      _echoTimer?.cancel();
    });
    return PreCallState(channelId: _config.defaultChannelId);
  }

  int get localUid => _localUid;

  /// The call and this screen share one engine, so while a call is joining
  /// or live, preview and camera changes here would reach the call.
  bool get _isCallBusy => ref.read(callControllerProvider).isBusy;

  /// Asks for permissions, starts the engine and the camera preview.
  Future<void> prepare() async {
    if (state.status == PreCallStatus.preparing || _isCallBusy) return;
    if (state.isReady) {
      await _engine.startPreview();
      return;
    }
    state = state.copyWith(
      status: PreCallStatus.preparing,
      failure: () => null,
      failureDetail: () => null,
    );

    if (!_config.isConfigured) {
      _fail(PreCallFailure.notConfigured);
      return;
    }

    final permission = await _permissions.requestCameraAndMic();
    if (!ref.mounted) return;
    switch (permission) {
      case CallPermissionResult.denied:
        _fail(PreCallFailure.permissionDenied);
        return;
      case CallPermissionResult.permanentlyDenied:
        _fail(PreCallFailure.permissionPermanentlyDenied);
        return;
      case CallPermissionResult.granted:
        break;
    }

    try {
      await _engine.initialize(appId: _config.appId);
      await ref.read(mediaSettingsControllerProvider.notifier).applyAll();
      await _engine.startPreview();
      if (!ref.mounted) return;
      state = state.copyWith(status: PreCallStatus.ready);
      _log('Engine ready, preview on');
    } catch (error) {
      if (!ref.mounted) return;
      _fail(PreCallFailure.engineError, detail: '$error');
    }
  }

  Future<void> openPermissionSettings() => _permissions.openSettings();

  /// Called when the app returns to the foreground. If access was blocked
  /// and the user has since allowed it in Settings, start again. Only
  /// checks, never asks: asking here would re-open Android's dialog every
  /// time that dialog closes.
  Future<void> recheckPermissions() async {
    final failure = state.failure;
    if (failure != PreCallFailure.permissionDenied &&
        failure != PreCallFailure.permissionPermanentlyDenied) {
      return;
    }
    if (!await _permissions.hasCameraAndMic() || !ref.mounted) return;
    _log('Camera and microphone now allowed → starting again');
    await prepare();
  }

  void setDisplayName(String name) => state = state.copyWith(displayName: name);

  void setChannelId(String channelId) =>
      state = state.copyWith(channelId: channelId.trim());

  void setRole(ParticipantRole role) => state = state.copyWith(role: role);

  void toggleStartWithMic() =>
      state = state.copyWith(startWithMic: !state.startWithMic);

  Future<void> toggleStartWithCamera() async {
    final enabled = !state.startWithCamera;
    state = state.copyWith(startWithCamera: enabled);
    if (!state.isReady || _isCallBusy) return;
    try {
      await _engine.setCameraEnabled(enabled);
    } catch (error) {
      _log('Preview camera toggle failed: $error');
    }
  }

  void toggleEncryption() =>
      state = state.copyWith(isEncryptionOn: !state.isEncryptionOn);

  void setEncryptionPassphrase(String passphrase) =>
      state = state.copyWith(encryptionPassphrase: passphrase);

  Future<void> toggleEchoTest() async {
    if (!state.isReady) return;
    if (state.echoStatus == EchoTestStatus.running) {
      await _stopEchoTest();
      return;
    }
    state = state.copyWith(
      echoStatus: EchoTestStatus.starting,
      echoError: () => null,
    );
    try {
      final channelId = 'echo-$_localUid';
      final token = await _tokens.rtcToken(
        channelId: channelId,
        uid: _echoTokenUid,
      );
      await _tests.startEchoTest(
        channelId: channelId,
        token: token,
        delaySeconds: echoDelaySeconds,
      );
      if (!ref.mounted) return;
      state = state.copyWith(echoStatus: EchoTestStatus.running);
      _log('Echo test started');
      _echoTimer?.cancel();
      _echoTimer = Timer(_echoTestDuration, _stopEchoTest);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        echoStatus: EchoTestStatus.failed,
        echoError: () => '$error',
      );
      _log('Echo test failed: $error');
    }
  }

  Future<void> toggleNetworkTest() async {
    if (!state.isReady) return;
    if (state.networkStatus == NetworkTestStatus.running) {
      await _stopNetworkTest(NetworkTestStatus.idle);
      return;
    }
    state = state.copyWith(
      networkStatus: NetworkTestStatus.running,
      networkQuality: () => null,
      networkResult: () => null,
    );
    try {
      await _tests.startNetworkTest();
      _log('Network test started');
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(networkStatus: NetworkTestStatus.failed);
      _log('Network test failed: $error');
    }
  }

  /// Stops tests and hands back a session for the call, or null when the
  /// form isn't valid yet.
  Future<CallSession?> finish() async {
    if (!state.canJoin) return null;
    await _stopEchoTest();
    if (state.networkStatus == NetworkTestStatus.running) {
      await _stopNetworkTest(NetworkTestStatus.idle);
    }
    final name = state.displayName.trim();
    return CallSession(
      channelId: state.channelId,
      localUid: _localUid,
      screenShareUid: _screenShareUid,
      displayName: name.isEmpty ? 'Guest ${_localUid % 10000}' : name,
      role: state.role,
      startWithMic: state.startWithMic,
      startWithCamera: state.startWithCamera,
      encryptionPassphrase: state.isEncryptionOn
          ? state.encryptionPassphrase
          : '',
    );
  }

  /// Leaving the pre-call screen without joining.
  Future<void> cancel() async {
    await _stopEchoTest();
    if (state.networkStatus == NetworkTestStatus.running) {
      await _stopNetworkTest(NetworkTestStatus.idle);
    }
    // Stopping the preview mid-call would stop the call's camera.
    if (!state.isReady || _isCallBusy) return;
    try {
      await _engine.stopPreview();
    } catch (error) {
      _log('Stop preview failed: $error');
    }
  }

  void _onEngineEvent(CallEvent event) {
    if (!ref.mounted || state.networkStatus != NetworkTestStatus.running) {
      return;
    }
    switch (event) {
      case NetworkTestQuality(:final quality):
        state = state.copyWith(networkQuality: () => quality);
        _log('Network test first verdict: ${quality.name}');
      case NetworkTestCompleted(:final result):
        state = state.copyWith(networkResult: () => result);
        _log(
          'Network test: up ${result.uplinkKbps} kbps '
          '${result.uplinkLossPercent}% loss, down ${result.downlinkKbps} kbps '
          '${result.downlinkLossPercent}% loss, RTT ${result.roundTripMs} ms',
        );
        unawaited(_stopNetworkTest(NetworkTestStatus.done));
      default:
        break;
    }
  }

  Future<void> _stopEchoTest() async {
    _echoTimer?.cancel();
    if (state.echoStatus != EchoTestStatus.running) return;
    try {
      await _tests.stopEchoTest();
    } catch (error) {
      _log('Stop echo test failed: $error');
    }
    if (!ref.mounted) return;
    state = state.copyWith(echoStatus: EchoTestStatus.idle);
    _log('Echo test stopped');
  }

  Future<void> _stopNetworkTest(NetworkTestStatus next) async {
    try {
      await _tests.stopNetworkTest();
    } catch (error) {
      _log('Stop network test failed: $error');
    }
    if (!ref.mounted) return;
    state = state.copyWith(networkStatus: next);
  }

  void _fail(PreCallFailure failure, {String? detail}) {
    _log(
      'Pre-call failed: ${failure.name}${detail == null ? '' : ' ($detail)'}',
    );
    state = state.copyWith(
      status: PreCallStatus.failed,
      failure: () => failure,
      failureDetail: () => detail,
    );
  }

  void _log(String message) => ref.read(callLogProvider.notifier).add(message);
}
