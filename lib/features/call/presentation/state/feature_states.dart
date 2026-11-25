import 'package:flutter/foundation.dart';

import '../../domain/call_engine.dart';
import '../../domain/call_metrics.dart';

@immutable
class CallLogEntry {
  const CallLogEntry({required this.at, required this.message});
  final DateTime at;
  final String message;
}

@immutable
class MediaSettings {
  const MediaSettings({
    this.quality = VideoQuality.standard,
    this.isNoiseSuppressionOn = false,
    this.isBlurOn = false,
    this.isBeautyOn = false,
    this.isAudioOnly = false,
    this.isBlurSupported,
  });

  final VideoQuality quality;
  final bool isNoiseSuppressionOn;
  final bool isBlurOn;
  final bool isBeautyOn;
  final bool isAudioOnly;

  /// Null until the device has been asked.
  final bool? isBlurSupported;

  MediaSettings copyWith({
    VideoQuality? quality,
    bool? isNoiseSuppressionOn,
    bool? isBlurOn,
    bool? isBeautyOn,
    bool? isAudioOnly,
    bool? isBlurSupported,
  }) => MediaSettings(
    quality: quality ?? this.quality,
    isNoiseSuppressionOn: isNoiseSuppressionOn ?? this.isNoiseSuppressionOn,
    isBlurOn: isBlurOn ?? this.isBlurOn,
    isBeautyOn: isBeautyOn ?? this.isBeautyOn,
    isAudioOnly: isAudioOnly ?? this.isAudioOnly,
    isBlurSupported: isBlurSupported ?? this.isBlurSupported,
  );
}

@immutable
class ChatEntry {
  const ChatEntry({
    required this.fromUid,
    required this.text,
    required this.at,
    required this.isMine,
  });

  final int fromUid;
  final String text;
  final DateTime at;
  final bool isMine;
}

@immutable
class ChatState {
  const ChatState({
    this.entries = const [],
    this.unreadCount = 0,
    this.isOpen = false,
    this.sendError,
  });

  final List<ChatEntry> entries;
  final int unreadCount;
  final bool isOpen;
  final String? sendError;

  ChatState copyWith({
    List<ChatEntry>? entries,
    int? unreadCount,
    bool? isOpen,
    ValueGetter<String?>? sendError,
  }) => ChatState(
    entries: entries ?? this.entries,
    unreadCount: unreadCount ?? this.unreadCount,
    isOpen: isOpen ?? this.isOpen,
    sendError: sendError != null ? sendError() : this.sendError,
  );
}

@immutable
class StatsState {
  const StatsState({
    this.call,
    this.localVideo,
    this.remoteVideo = const {},
    this.remoteAudio = const {},
    this.isOverlayVisible = false,
  });

  final CallStats? call;
  final LocalVideoMetrics? localVideo;
  final Map<int, RemoteVideoMetrics> remoteVideo;
  final Map<int, RemoteAudioMetrics> remoteAudio;
  final bool isOverlayVisible;

  StatsState copyWith({
    CallStats? call,
    LocalVideoMetrics? localVideo,
    Map<int, RemoteVideoMetrics>? remoteVideo,
    Map<int, RemoteAudioMetrics>? remoteAudio,
    bool? isOverlayVisible,
  }) => StatsState(
    call: call ?? this.call,
    localVideo: localVideo ?? this.localVideo,
    remoteVideo: remoteVideo ?? this.remoteVideo,
    remoteAudio: remoteAudio ?? this.remoteAudio,
    isOverlayVisible: isOverlayVisible ?? this.isOverlayVisible,
  );
}

@immutable
class CaptureState {
  const CaptureState({
    this.isRecording = false,
    this.recordingUid,
    this.recordingPath,
    this.recordingDurationMs = 0,
    this.recordingBytes = 0,
    this.lastRecordingPath,
    this.lastSnapshotPath,
    this.message,
  });

  final bool isRecording;
  final int? recordingUid;
  final String? recordingPath;
  final int recordingDurationMs;
  final int recordingBytes;
  final String? lastRecordingPath;
  final String? lastSnapshotPath;

  /// One-off notice for a snackbar (errors, saved paths).
  final String? message;

  CaptureState copyWith({
    bool? isRecording,
    ValueGetter<int?>? recordingUid,
    ValueGetter<String?>? recordingPath,
    int? recordingDurationMs,
    int? recordingBytes,
    String? lastRecordingPath,
    String? lastSnapshotPath,
    ValueGetter<String?>? message,
  }) => CaptureState(
    isRecording: isRecording ?? this.isRecording,
    recordingUid: recordingUid != null ? recordingUid() : this.recordingUid,
    recordingPath: recordingPath != null ? recordingPath() : this.recordingPath,
    recordingDurationMs: recordingDurationMs ?? this.recordingDurationMs,
    recordingBytes: recordingBytes ?? this.recordingBytes,
    lastRecordingPath: lastRecordingPath ?? this.lastRecordingPath,
    lastSnapshotPath: lastSnapshotPath ?? this.lastSnapshotPath,
    message: message != null ? message() : this.message,
  );
}
