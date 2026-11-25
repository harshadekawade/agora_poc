import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../domain/call_engine.dart';
import '../../domain/call_metrics.dart';

/// Owns the one native Agora engine and turns its callbacks into
/// vendor-neutral [CallEvent]s (Adapter pattern).
///
/// The feature adapters (core call, effects, messaging, capture, pre-call
/// tests) all share this host, so there is exactly one engine and one
/// event stream however many interfaces the app uses.
class AgoraEngineHost {
  AgoraEngineHost({
    RtcEngineEx Function() engineFactory = createAgoraRtcEngineEx,
  }) : _engineFactory = engineFactory;

  /// Agora reports the local user as uid 0 in volume and quality callbacks.
  static const localUserId = 0;

  /// Volume report interval. Agora recommends ≥ 200 ms.
  static const _volumeIntervalMs = 300;
  static const _volumeSmoothing = 3;

  /// Values of Agora's AudioRoute enum, which callbacks report as raw ints.
  static const _audioRouteNames = {
    -1: 'default',
    0: 'wired headset',
    1: 'earpiece',
    2: 'headset (no mic)',
    3: 'speakerphone',
    4: 'loudspeaker',
    5: 'bluetooth',
    6: 'USB',
    7: 'HDMI',
    8: 'DisplayPort',
    9: 'AirPlay',
    10: 'bluetooth (A2DP)',
  };

  final RtcEngineEx Function() _engineFactory;
  final _events = StreamController<CallEvent>.broadcast();

  RtcEngineEx? _engine;
  RtcEngineEventHandler? _handler;

  /// Channel of the current call (set on join).
  String? channelId;

  /// Our camera identity in the current call.
  int? localUid;

  /// Our screen-share identity while sharing, else null.
  int? get screenShareUid => _activeScreenUid;

  int? _activeScreenUid;

  /// Every screen uid used this call. Agora reports the screen connection's
  /// leave events *after* sharing stops, so they must still be recognised.
  final Set<int> _ownScreenUids = {};

  void startedScreenShare(int uid) {
    _activeScreenUid = uid;
    _ownScreenUids.add(uid);
  }

  void stoppedScreenShare() => _activeScreenUid = null;

  Stream<CallEvent> get events => _events.stream;

  bool get isInitialized => _engine != null;

  RtcEngineEx get engine =>
      _engine ?? (throw StateError('Agora engine not initialized'));

  Future<void> initialize({required String appId}) async {
    if (_engine != null) return;

    final engine = _engineFactory();
    await engine.initialize(
      RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ),
    );
    final handler = _buildHandler();
    engine.registerEventHandler(handler);
    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await engine.enableVideo();
    // A video consult is held at arm's length, so default to the loudspeaker.
    await engine.setDefaultAudioRouteToSpeakerphone(true);
    await engine.enableAudioVolumeIndication(
      interval: _volumeIntervalMs,
      smooth: _volumeSmoothing,
      reportVad: true,
    );
    // Publish a second, small stream so grid thumbnails can use it.
    await engine.enableDualStreamMode(enabled: true);

    _engine = engine;
    _handler = handler;
  }

  void emit(CallEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> dispose() async {
    final engine = _engine;
    final handler = _handler;
    _engine = null;
    _handler = null;
    if (engine != null) {
      if (handler != null) engine.unregisterEventHandler(handler);
      await engine.release();
    }
    await _events.close();
  }

  static const _tokenRejections = {
    ConnectionChangedReasonType.connectionChangedInvalidToken,
    ConnectionChangedReasonType.connectionChangedTokenExpired,
  };

  bool _isScreenConnection(RtcConnection connection) =>
      _ownScreenUids.contains(connection.localUid);

  /// Our own screen share shows up as a remote user on the camera
  /// connection; it is handled separately, never as a participant.
  bool _isOwnScreen(int uid) => _ownScreenUids.contains(uid);

  bool _ignore(RtcConnection connection, [int? remoteUid]) =>
      _isScreenConnection(connection) ||
      (remoteUid != null && _isOwnScreen(remoteUid));

  RtcEngineEventHandler _buildHandler() => RtcEngineEventHandler(
    onJoinChannelSuccess: (connection, elapsed) {
      if (_isScreenConnection(connection)) return;
      emit(CallJoined(localUid: connection.localUid ?? 0, elapsedMs: elapsed));
    },
    onLeaveChannel: (connection, _) {
      if (_isScreenConnection(connection)) return;
      _ownScreenUids.clear();
      _activeScreenUid = null;
      emit(const CallLeft());
    },
    onUserJoined: (connection, uid, _) {
      if (_isScreenConnection(connection)) return;
      if (_isOwnScreen(uid)) {
        // Don't download our own screen back from Agora.
        unawaited(engine.muteRemoteVideoStream(uid: uid, mute: true));
        unawaited(engine.muteRemoteAudioStream(uid: uid, mute: true));
        return;
      }
      emit(RemoteUserJoined(uid));
    },
    onUserOffline: (connection, uid, reason) {
      if (_ignore(connection, uid)) return;
      emit(RemoteUserLeft(uid: uid, reason: reason.name));
    },
    onRemoteVideoStateChanged: (connection, uid, state, _, _) {
      if (_ignore(connection, uid)) return;
      emit(RemoteVideoChanged(uid: uid, status: _mapRemoteVideo(state)));
    },
    // Agora's "publishing video or not" signal. Only "stopped" is mapped:
    // when video resumes, onRemoteVideoStateChanged reports it in full.
    onUserMuteVideo: (connection, uid, muted) {
      if (!muted || _ignore(connection, uid)) return;
      emit(RemoteVideoChanged(uid: uid, status: RemoteVideoStatus.off));
    },
    onUserMuteAudio: (connection, uid, muted) {
      if (_ignore(connection, uid)) return;
      emit(RemoteAudioMuted(uid: uid, muted: muted));
    },
    onConnectionStateChanged: (connection, state, reason) {
      if (_isScreenConnection(connection)) return;
      emit(
        ConnectionChanged(
          state: _mapConnection(state),
          reason: reason.name,
          isTokenRejected: _tokenRejections.contains(reason),
        ),
      );
    },
    onNetworkQuality: (connection, uid, tx, rx) {
      if (_isScreenConnection(connection) || uid != localUserId) return;
      emit(
        NetworkQualityChanged(
          uplink: _mapQuality(tx),
          downlink: _mapQuality(rx),
        ),
      );
    },
    onTokenPrivilegeWillExpire: (connection, _) =>
        emit(TokenWillExpire(localUid: connection.localUid ?? 0)),
    onRequestToken: (connection) =>
        emit(TokenExpired(localUid: connection.localUid ?? 0)),
    onAudioRoutingChanged: (routing) => emit(
      AudioRouteChanged(_audioRouteNames[routing] ?? 'unknown ($routing)'),
    ),
    onError: (err, msg) =>
        emit(CallErrorOccurred(code: err.name, message: msg)),
    onAudioVolumeIndication: (connection, speakers, _, _) {
      if (_isScreenConnection(connection)) return;
      emit(
        VolumesUpdated({
          for (final speaker in speakers)
            if (!_isOwnScreen(speaker.uid ?? localUserId))
              speaker.uid ?? localUserId: speaker.volume ?? 0,
        }),
      );
    },
    onActiveSpeaker: (connection, uid) {
      if (_ignore(connection, uid)) return;
      emit(ActiveSpeakerChanged(uid));
    },
    onRtcStats: (connection, stats) {
      if (_isScreenConnection(connection)) return;
      emit(CallStatsUpdated(_mapCallStats(stats)));
    },
    onLocalVideoStats: (connection, source, stats) {
      if (_isScreenConnection(connection) || _isScreenSource(source)) return;
      emit(
        LocalVideoStatsUpdated(
          LocalVideoMetrics(
            width: stats.encodedFrameWidth ?? 0,
            height: stats.encodedFrameHeight ?? 0,
            frameRate: stats.sentFrameRate ?? 0,
            bitrateKbps: stats.sentBitrate ?? 0,
          ),
        ),
      );
    },
    onRemoteVideoStats: (connection, stats) {
      final uid = stats.uid ?? 0;
      if (_ignore(connection, uid)) return;
      emit(RemoteVideoStatsUpdated(_mapRemoteVideoStats(uid, stats)));
    },
    onRemoteAudioStats: (connection, stats) {
      final uid = stats.uid ?? 0;
      if (_ignore(connection, uid)) return;
      emit(
        RemoteAudioStatsUpdated(
          RemoteAudioMetrics(
            uid: uid,
            lossPercent: stats.audioLossRate ?? 0,
            jitterMs: stats.jitterBufferDelay ?? 0,
            delayMs: stats.networkTransportDelay ?? 0,
          ),
        ),
      );
    },
    onStreamMessage: (connection, uid, _, data, _, _) {
      if (_ignore(connection, uid)) return;
      emit(DataMessageReceived(fromUid: uid, bytes: data));
    },
    onSnapshotTaken: (connection, uid, filePath, _, _, errorCode) => emit(
      SnapshotTaken(uid: uid, filePath: filePath, isSuccess: errorCode == 0),
    ),
    onLocalVideoStateChanged: (source, state, reason) {
      if (!_isScreenSource(source)) return;
      final status = switch (state) {
        LocalVideoStreamState.localVideoStreamStateCapturing ||
        LocalVideoStreamState.localVideoStreamStateEncoding =>
          ScreenShareStatus.active,
        LocalVideoStreamState.localVideoStreamStateStopped =>
          ScreenShareStatus.stopped,
        LocalVideoStreamState.localVideoStreamStateFailed =>
          ScreenShareStatus.failed,
      };
      emit(ScreenShareStateChanged(status: status, detail: reason.name));
    },
    onLastmileQuality: (quality) =>
        emit(NetworkTestQuality(_mapQuality(quality))),
    onLastmileProbeResult: (result) =>
        emit(NetworkTestCompleted(_mapProbeResult(result))),
  );

  static bool _isScreenSource(VideoSourceType source) =>
      source == VideoSourceType.videoSourceScreen ||
      source == VideoSourceType.videoSourceScreenPrimary;

  static CallStats _mapCallStats(RtcStats stats) => CallStats(
    durationSeconds: stats.duration ?? 0,
    sendKbps: stats.txKBitRate ?? 0,
    receiveKbps: stats.rxKBitRate ?? 0,
    roundTripMs: stats.lastmileDelay ?? 0,
    sendLossPercent: stats.txPacketLossRate ?? 0,
    receiveLossPercent: stats.rxPacketLossRate ?? 0,
    appCpuPercent: stats.cpuAppUsage ?? 0,
    userCount: stats.userCount ?? 0,
  );

  static RemoteVideoMetrics _mapRemoteVideoStats(
    int uid,
    RemoteVideoStats stats,
  ) => RemoteVideoMetrics(
    uid: uid,
    width: stats.width ?? 0,
    height: stats.height ?? 0,
    frameRate: stats.rendererOutputFrameRate ?? 0,
    bitrateKbps: stats.receivedBitrate ?? 0,
    packetLossPercent: stats.packetLossRate ?? 0,
    frozenRatePercent: stats.frozenRate ?? 0,
    delayMs: stats.delay ?? 0,
    isLowStream: stats.rxStreamType == VideoStreamType.videoStreamLow,
  );

  static const _bitsPerKilobit = 1000;

  static NetworkTestResult _mapProbeResult(LastmileProbeResult result) {
    final up = result.uplinkReport;
    final down = result.downlinkReport;
    return NetworkTestResult(
      isComplete:
          result.state == LastmileProbeResultState.lastmileProbeResultComplete,
      roundTripMs: result.rtt ?? 0,
      uplinkKbps: (up?.availableBandwidth ?? 0) ~/ _bitsPerKilobit,
      uplinkLossPercent: up?.packetLossRate ?? 0,
      uplinkJitterMs: up?.jitter ?? 0,
      downlinkKbps: (down?.availableBandwidth ?? 0) ~/ _bitsPerKilobit,
      downlinkLossPercent: down?.packetLossRate ?? 0,
      downlinkJitterMs: down?.jitter ?? 0,
    );
  }

  static RemoteVideoStatus _mapRemoteVideo(RemoteVideoState state) =>
      switch (state) {
        RemoteVideoState.remoteVideoStateStarting =>
          RemoteVideoStatus.connecting,
        RemoteVideoState.remoteVideoStateDecoding => RemoteVideoStatus.on,
        RemoteVideoState.remoteVideoStateFrozen => RemoteVideoStatus.frozen,
        RemoteVideoState.remoteVideoStateStopped ||
        RemoteVideoState.remoteVideoStateFailed => RemoteVideoStatus.off,
      };

  static CallConnectionState _mapConnection(ConnectionStateType state) =>
      switch (state) {
        ConnectionStateType.connectionStateDisconnected =>
          CallConnectionState.disconnected,
        ConnectionStateType.connectionStateConnecting =>
          CallConnectionState.connecting,
        ConnectionStateType.connectionStateConnected =>
          CallConnectionState.connected,
        ConnectionStateType.connectionStateReconnecting =>
          CallConnectionState.reconnecting,
        ConnectionStateType.connectionStateFailed => CallConnectionState.failed,
      };

  static CallNetworkQuality _mapQuality(QualityType quality) =>
      switch (quality) {
        QualityType.qualityExcellent => CallNetworkQuality.excellent,
        QualityType.qualityGood => CallNetworkQuality.good,
        QualityType.qualityPoor => CallNetworkQuality.poor,
        QualityType.qualityBad => CallNetworkQuality.bad,
        QualityType.qualityVbad => CallNetworkQuality.veryBad,
        QualityType.qualityDown => CallNetworkQuality.down,
        _ => CallNetworkQuality.unknown,
      };
}
