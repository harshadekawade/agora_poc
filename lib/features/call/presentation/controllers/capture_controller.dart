import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/call_engine.dart';
import '../providers/call_providers.dart';
import '../state/feature_states.dart';

/// Snapshots and on-device recording.
class CaptureController extends Notifier<CaptureState> {
  late CallCapture _capture;
  late Future<Directory> Function() _directory;

  @override
  CaptureState build() {
    _capture = ref.watch(callCaptureProvider);
    _directory = ref.watch(captureDirectoryProvider);
    final events = ref.watch(callEngineProvider).events.listen(_onEvent);
    ref.onDispose(events.cancel);
    return const CaptureState();
  }

  /// [uid] 0 = our own camera.
  Future<void> takeSnapshot(int uid) async {
    try {
      final path = await _newFilePath('snapshot_$uid', 'jpg');
      await _capture.takeSnapshot(uid: uid, filePath: path);
      _log('Snapshot requested for uid $uid → $path');
    } catch (error) {
      _notify('Snapshot failed: $error');
    }
  }

  /// Records [uid]'s audio+video to an MP4 on this phone.
  Future<void> toggleRecording({
    required String channelId,
    required int uid,
  }) async {
    if (state.isRecording) {
      await _stop();
      return;
    }
    try {
      final path = await _newFilePath('recording_$uid', 'mp4');
      await _capture.startRecording(
        channelId: channelId,
        uid: uid,
        filePath: path,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        isRecording: true,
        recordingUid: () => uid,
        recordingPath: () => path,
        recordingDurationMs: 0,
        recordingBytes: 0,
      );
      _log('Recording uid $uid → $path');
    } catch (error) {
      _notify('Recording failed to start: $error');
    }
  }

  void clearMessage() => state = state.copyWith(message: () => null);

  Future<void> _stop() async {
    final path = state.recordingPath;
    try {
      await _capture.stopRecording();
    } catch (error) {
      _log('Stop recording error: $error');
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      isRecording: false,
      recordingUid: () => null,
      recordingPath: () => null,
      lastRecordingPath: path,
    );
    if (path != null) _notify('Recording saved: $path');
  }

  void _onEvent(CallEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case SnapshotTaken(:final uid, :final filePath, :final isSuccess):
        if (isSuccess) {
          state = state.copyWith(lastSnapshotPath: filePath);
          _notify('Snapshot saved: $filePath');
        } else {
          _notify('Snapshot of uid $uid failed');
        }
      case RecordingStateChanged(:final status, :final detail):
        _log('Recorder ${status.name} ($detail)');
        if (status == RecordingStatus.failed) {
          unawaited(_stop());
        }
      case RecordingProgress(:final durationMs, :final fileSize):
        state = state.copyWith(
          recordingDurationMs: durationMs,
          recordingBytes: fileSize,
        );
      case CallLeft():
        if (state.isRecording) unawaited(_stop());
      default:
        break;
    }
  }

  Future<String> _newFilePath(String prefix, String extension) async {
    final directory = await _directory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${directory.path}${Platform.pathSeparator}${prefix}_$stamp.$extension';
  }

  void _notify(String message) {
    _log(message);
    if (!ref.mounted) return;
    state = state.copyWith(message: () => message);
  }

  void _log(String message) {
    if (!ref.mounted) return;
    ref.read(callLogProvider.notifier).add(message);
  }
}
