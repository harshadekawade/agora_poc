import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';

import '../../domain/call_engine.dart';
import 'agora_engine_host.dart';

class AgoraCallCapture implements CallCapture {
  AgoraCallCapture(this._host);

  // Tuned for slow mobile uploads (a POC test at 400 kbps upload starved a
  // 720p/15 fps screen to ~4 kbps): 540×960 still reads text on a phone,
  // 10 fps is enough for slides and forms, and the cap leaves room for the
  // camera and audio.
  static const _screenWidth = 540;
  static const _screenHeight = 960;
  static const _screenFrameRate = 10;
  static const _screenMaxBitrateKbps = 600;
  static const _screenDimensions = VideoDimensions(
    width: _screenWidth,
    height: _screenHeight,
  );

  /// POC cap so a forgotten recording can't fill the phone.
  static const _maxRecordingMs = 5 * 60 * 1000;
  static const _recordingInfoIntervalMs = 1000;

  final AgoraEngineHost _host;
  MediaRecorder? _recorder;

  /// iOS needs a separate Broadcast Upload Extension target (built on a Mac),
  /// which this POC doesn't include.
  @override
  bool get isScreenShareSupported =>
      defaultTargetPlatform == TargetPlatform.android;

  RtcConnection _screenConnection(String channelId, int shareUid) =>
      RtcConnection(channelId: channelId, localUid: shareUid);

  @override
  Future<void> startScreenShare({
    required String channelId,
    required int shareUid,
    required String token,
  }) async {
    if (!isScreenShareSupported) {
      throw UnsupportedError('Screen sharing needs an iOS extension');
    }
    // A half-started share (e.g. the permission dialog was lost) is still
    // in the room; joining again would fail with -17 "already joined".
    if (_host.screenShareUid != null) await stopScreenShare();
    // Set before joining so the camera connection ignores our own screen.
    _host.startedScreenShare(shareUid);
    try {
      await _startCaptureAndJoin(channelId, shareUid, token);
    } catch (_) {
      await stopScreenShare();
      rethrow;
    }
  }

  Future<void> _startCaptureAndJoin(
    String channelId,
    int shareUid,
    String token,
  ) async {
    final engine = _host.engine;
    await engine.startScreenCapture(
      const ScreenCaptureParameters2(
        captureAudio: false,
        captureVideo: true,
        videoParams: ScreenVideoParameters(
          dimensions: _screenDimensions,
          frameRate: _screenFrameRate,
          bitrate: _screenMaxBitrateKbps,
          contentHint: VideoContentHint.contentHintDetails,
        ),
      ),
    );
    await engine.joinChannelEx(
      token: token,
      connection: _screenConnection(channelId, shareUid),
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishScreenCaptureVideo: true,
        publishScreenTrack: true,
        publishCameraTrack: false,
        publishMicrophoneTrack: false,
        autoSubscribeAudio: false,
        autoSubscribeVideo: false,
      ),
    );
    // When upload is short, drop frames rather than resolution, so text in
    // the shared screen stays sharp.
    await engine.setVideoEncoderConfigurationEx(
      config: const VideoEncoderConfiguration(
        dimensions: _screenDimensions,
        frameRate: _screenFrameRate,
        bitrate: _screenMaxBitrateKbps,
        degradationPreference: DegradationPreference.maintainResolution,
      ),
      connection: _screenConnection(channelId, shareUid),
    );
  }

  @override
  Future<void> stopScreenShare() async {
    final shareUid = _host.screenShareUid;
    final channelId = _host.channelId;
    if (shareUid == null || channelId == null) return;
    final engine = _host.engine;
    // Always forget the share, even if Agora errors (e.g. it never fully
    // joined), so the next share starts clean.
    try {
      await engine.leaveChannelEx(
        connection: _screenConnection(channelId, shareUid),
      );
      await engine.stopScreenCapture();
    } finally {
      _host.stoppedScreenShare();
    }
  }

  @override
  Future<void> renewScreenShareToken(String token) async {
    final shareUid = _host.screenShareUid;
    final channelId = _host.channelId;
    if (shareUid == null || channelId == null) return;
    await _host.engine.updateChannelMediaOptionsEx(
      options: ChannelMediaOptions(token: token),
      connection: _screenConnection(channelId, shareUid),
    );
  }

  @override
  Future<void> takeSnapshot({required int uid, required String filePath}) =>
      _host.engine.takeSnapshot(uid: uid, filePath: filePath);

  @override
  Future<void> startRecording({
    required String channelId,
    required int uid,
    required String filePath,
  }) async {
    await stopRecording();
    final recorder = await _host.engine.createMediaRecorder(
      RecorderStreamInfo(
        channelId: channelId,
        uid: uid,
        type: RecorderStreamType.rtc,
      ),
    );
    if (recorder == null) {
      throw StateError('Agora could not create a media recorder');
    }
    _recorder = recorder;
    await recorder.setMediaRecorderObserver(
      MediaRecorderObserver(
        onRecorderStateChanged: (_, _, state, reason) => _host.emit(
          RecordingStateChanged(
            status: switch (state) {
              RecorderState.recorderStateStart => RecordingStatus.recording,
              RecorderState.recorderStateStop => RecordingStatus.stopped,
              RecorderState.recorderStateError => RecordingStatus.failed,
            },
            detail: reason.name,
          ),
        ),
        onRecorderInfoUpdated: (_, _, info) => _host.emit(
          RecordingProgress(
            durationMs: info.durationMs ?? 0,
            fileSize: info.fileSize ?? 0,
          ),
        ),
      ),
    );
    await recorder.startRecording(
      MediaRecorderConfiguration(
        storagePath: filePath,
        containerFormat: MediaRecorderContainerFormat.formatMp4,
        streamType: MediaRecorderStreamType.streamTypeBoth,
        maxDurationMs: _maxRecordingMs,
        recorderInfoUpdateInterval: _recordingInfoIntervalMs,
      ),
    );
  }

  @override
  Future<void> stopRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;
    _recorder = null;
    await recorder.stopRecording();
    await _host.engine.destroyMediaRecorder(recorder);
  }
}
