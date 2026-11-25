import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../domain/call_engine.dart';
import 'agora_engine_host.dart';

/// [CallEngine] on Agora RTC (agora_rtc_engine 6.6.4).
class AgoraCallEngine implements CallEngine {
  const AgoraCallEngine(this._host);

  final AgoraEngineHost _host;

  @override
  Stream<CallEvent> get events => _host.events;

  @override
  Future<void> initialize({required String appId}) =>
      _host.initialize(appId: appId);

  @override
  Future<void> startPreview() => _host.engine.startPreview();

  @override
  Future<void> stopPreview() => _host.engine.stopPreview();

  @override
  Future<void> join({
    required String channelId,
    required String token,
    required int uid,
  }) async {
    _host
      ..channelId = channelId
      ..localUid = uid;
    final engine = _host.engine;
    await engine.startPreview();
    await engine.joinChannel(
      token: token,
      channelId: channelId,
      uid: uid,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
      ),
    );
  }

  @override
  Future<void> leave() async {
    if (!_host.isInitialized) return;
    await _host.engine.leaveChannel();
    await _host.engine.stopPreview();
  }

  @override
  Future<void> renewToken(String token) => _host.engine.renewToken(token);

  @override
  Future<void> setMicMuted(bool muted) =>
      _host.engine.muteLocalAudioStream(muted);

  @override
  Future<void> setCameraEnabled(bool enabled) =>
      _host.engine.enableLocalVideo(enabled);

  @override
  Future<void> switchCamera() => _host.engine.switchCamera();

  @override
  Future<void> setSpeakerOn(bool speakerOn) =>
      _host.engine.setEnableSpeakerphone(speakerOn);

  @override
  Future<void> setOthersMuted(bool muted) =>
      _host.engine.muteAllRemoteAudioStreams(muted);

  @override
  Future<void> setRemoteVideoHighQuality({
    required int uid,
    required bool high,
  }) => _host.engine.setRemoteVideoStreamType(
    uid: uid,
    streamType: high
        ? VideoStreamType.videoStreamHigh
        : VideoStreamType.videoStreamLow,
  );

  @override
  Future<void> dispose() => _host.dispose();
}
