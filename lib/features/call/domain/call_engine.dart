import 'dart:typed_data';

import 'call_metrics.dart';

/// Vendor-neutral contract for the core of a video call.
///
/// Small companion interfaces ([MediaEffects], [CallMessaging], [CallCapture],
/// [PreCallTests]) cover the optional features, so each consumer depends only
/// on what it uses (Interface Segregation). The Agora adapter implements all
/// of them; another vendor could be swapped in by overriding providers.
abstract interface class CallEngine {
  /// Everything the engine reports while it is alive.
  Stream<CallEvent> get events;

  /// Creates the native engine. Safe to call more than once.
  Future<void> initialize({required String appId});

  Future<void> startPreview();

  Future<void> stopPreview();

  Future<void> join({
    required String channelId,
    required String token,
    required int uid,
  });

  Future<void> leave();

  Future<void> renewToken(String token);

  Future<void> setMicMuted(bool muted);

  /// Turns camera capture on or off (the camera light goes off too).
  Future<void> setCameraEnabled(bool enabled);

  Future<void> switchCamera();

  Future<void> setSpeakerOn(bool speakerOn);

  /// Stops playing everyone else's sound, including people who join later.
  /// They can still hear us.
  Future<void> setOthersMuted(bool muted);

  /// Full-quality stream for big tiles, the cheaper low stream for small ones.
  Future<void> setRemoteVideoHighQuality({
    required int uid,
    required bool high,
  });

  Future<void> dispose();
}

/// Audio/video processing and quality settings.
abstract interface class MediaEffects {
  Future<bool> isBackgroundBlurSupported();

  Future<void> setVideoQuality(VideoQuality quality);

  /// AI noise suppression. Agora bills this as an add-on.
  Future<void> setNoiseSuppression(bool enabled);

  Future<void> setBackgroundBlur(bool enabled);

  Future<void> setBeauty(bool enabled);

  /// Stops receiving everyone's video, to save bandwidth.
  Future<void> setAudioOnly(bool enabled);

  /// Media encryption. Must be set before joining; every participant needs
  /// the same passphrase. An empty passphrase turns encryption off.
  Future<void> setEncryption({
    required String passphrase,
    required String channelId,
  });
}

/// Small in-call messages to everyone in the channel (Agora data stream:
/// max 1 KB per message, 30 messages/s, no history, not stored).
abstract interface class CallMessaging {
  Future<void> send(Uint8List bytes);
}

abstract interface class CallCapture {
  bool get isScreenShareSupported;

  /// Shares the screen as a separate participant ([shareUid]), so the
  /// camera keeps running. Same approach as Agora's own example.
  Future<void> startScreenShare({
    required String channelId,
    required int shareUid,
    required String token,
  });

  Future<void> stopScreenShare();

  Future<void> renewScreenShareToken(String token);

  /// [uid] 0 means our own camera.
  Future<void> takeSnapshot({required int uid, required String filePath});

  /// Records one participant's audio+video to an MP4 on this device.
  /// [uid] 0 means our own camera.
  Future<void> startRecording({
    required String channelId,
    required int uid,
    required String filePath,
  });

  Future<void> stopRecording();
}

abstract interface class PreCallTests {
  /// Plays back what the mic hears after [delaySeconds], to check mic and
  /// speaker together.
  Future<void> startEchoTest({
    required String channelId,
    required String token,
    required int delaySeconds,
  });

  Future<void> stopEchoTest();

  /// Measures bandwidth, loss and round-trip time to Agora's network.
  Future<void> startNetworkTest();

  Future<void> stopNetworkTest();
}

/// Encoder presets. Agora bills by the resolution people *receive*, so
/// higher presets also cost more per minute.
enum VideoQuality {
  low(width: 320, height: 240, frameRate: 15),
  standard(width: 640, height: 360, frameRate: 15),
  hd(width: 1280, height: 720, frameRate: 15),
  fullHd(width: 1920, height: 1080, frameRate: 15);

  const VideoQuality({
    required this.width,
    required this.height,
    required this.frameRate,
  });

  final int width;
  final int height;
  final int frameRate;
}

enum CallConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

enum CallNetworkQuality { unknown, excellent, good, poor, bad, veryBad, down }

/// [connecting]: subscribed but no frame yet (Agora "starting").
enum RemoteVideoStatus { connecting, on, off, frozen }

enum ScreenShareStatus { active, stopped, failed }

enum RecordingStatus { recording, stopped, failed }

sealed class CallEvent {
  const CallEvent();
}

final class CallJoined extends CallEvent {
  const CallJoined({required this.localUid, required this.elapsedMs});
  final int localUid;
  final int elapsedMs;
}

final class CallLeft extends CallEvent {
  const CallLeft();
}

final class RemoteUserJoined extends CallEvent {
  const RemoteUserJoined(this.uid);
  final int uid;
}

final class RemoteUserLeft extends CallEvent {
  const RemoteUserLeft({required this.uid, required this.reason});
  final int uid;
  final String reason;
}

final class RemoteVideoChanged extends CallEvent {
  const RemoteVideoChanged({required this.uid, required this.status});
  final int uid;
  final RemoteVideoStatus status;
}

final class RemoteAudioMuted extends CallEvent {
  const RemoteAudioMuted({required this.uid, required this.muted});
  final int uid;
  final bool muted;
}

final class ConnectionChanged extends CallEvent {
  const ConnectionChanged({
    required this.state,
    required this.reason,
    this.isTokenRejected = false,
  });
  final CallConnectionState state;

  /// The vendor's reason, for the log only (not user-facing text).
  final String reason;

  /// The server refused the token: invalid, expired, or for another room.
  final bool isTokenRejected;
}

/// Local user's own network quality (uplink = sending, downlink = receiving).
final class NetworkQualityChanged extends CallEvent {
  const NetworkQualityChanged({required this.uplink, required this.downlink});
  final CallNetworkQuality uplink;
  final CallNetworkQuality downlink;
}

/// [localUid] says which of our connections it is for (camera or screen).
final class TokenWillExpire extends CallEvent {
  const TokenWillExpire({required this.localUid});
  final int localUid;
}

final class TokenExpired extends CallEvent {
  const TokenExpired({required this.localUid});
  final int localUid;
}

final class AudioRouteChanged extends CallEvent {
  const AudioRouteChanged(this.route);
  final String route;
}

final class CallErrorOccurred extends CallEvent {
  const CallErrorOccurred({required this.code, required this.message});
  final String code;
  final String message;
}

/// Volume 0–255 per uid; uid 0 is the local user.
final class VolumesUpdated extends CallEvent {
  const VolumesUpdated(this.volumes);
  final Map<int, int> volumes;
}

final class ActiveSpeakerChanged extends CallEvent {
  const ActiveSpeakerChanged(this.uid);
  final int uid;
}

final class CallStatsUpdated extends CallEvent {
  const CallStatsUpdated(this.stats);
  final CallStats stats;
}

final class LocalVideoStatsUpdated extends CallEvent {
  const LocalVideoStatsUpdated(this.metrics);
  final LocalVideoMetrics metrics;
}

final class RemoteVideoStatsUpdated extends CallEvent {
  const RemoteVideoStatsUpdated(this.metrics);
  final RemoteVideoMetrics metrics;
}

final class RemoteAudioStatsUpdated extends CallEvent {
  const RemoteAudioStatsUpdated(this.metrics);
  final RemoteAudioMetrics metrics;
}

final class DataMessageReceived extends CallEvent {
  const DataMessageReceived({required this.fromUid, required this.bytes});
  final int fromUid;
  final Uint8List bytes;
}

final class SnapshotTaken extends CallEvent {
  const SnapshotTaken({
    required this.uid,
    required this.filePath,
    required this.isSuccess,
  });
  final int uid;
  final String filePath;
  final bool isSuccess;
}

final class RecordingStateChanged extends CallEvent {
  const RecordingStateChanged({required this.status, this.detail});
  final RecordingStatus status;
  final String? detail;
}

final class RecordingProgress extends CallEvent {
  const RecordingProgress({required this.durationMs, required this.fileSize});
  final int durationMs;
  final int fileSize;
}

final class ScreenShareStateChanged extends CallEvent {
  const ScreenShareStateChanged({required this.status, this.detail});
  final ScreenShareStatus status;
  final String? detail;
}

/// Quick first verdict of the pre-call network test (~2 s).
final class NetworkTestQuality extends CallEvent {
  const NetworkTestQuality(this.quality);
  final CallNetworkQuality quality;
}

/// Full pre-call network test result (~30 s).
final class NetworkTestCompleted extends CallEvent {
  const NetworkTestCompleted(this.result);
  final NetworkTestResult result;
}
