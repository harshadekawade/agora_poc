import 'package:flutter/foundation.dart';

/// Whole-call numbers, reported about every 2 seconds.
@immutable
class CallStats {
  const CallStats({
    required this.durationSeconds,
    required this.sendKbps,
    required this.receiveKbps,
    required this.roundTripMs,
    required this.sendLossPercent,
    required this.receiveLossPercent,
    required this.appCpuPercent,
    required this.userCount,
  });

  final int durationSeconds;
  final int sendKbps;
  final int receiveKbps;
  final int roundTripMs;
  final int sendLossPercent;
  final int receiveLossPercent;
  final double appCpuPercent;
  final int userCount;
}

@immutable
class LocalVideoMetrics {
  const LocalVideoMetrics({
    required this.width,
    required this.height,
    required this.frameRate,
    required this.bitrateKbps,
  });

  final int width;
  final int height;
  final int frameRate;
  final int bitrateKbps;
}

@immutable
class RemoteVideoMetrics {
  const RemoteVideoMetrics({
    required this.uid,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.bitrateKbps,
    required this.packetLossPercent,
    required this.frozenRatePercent,
    required this.delayMs,
    required this.isLowStream,
  });

  final int uid;
  final int width;
  final int height;
  final int frameRate;
  final int bitrateKbps;
  final int packetLossPercent;
  final int frozenRatePercent;
  final int delayMs;
  final bool isLowStream;
}

@immutable
class RemoteAudioMetrics {
  const RemoteAudioMetrics({
    required this.uid,
    required this.lossPercent,
    required this.jitterMs,
    required this.delayMs,
  });

  final int uid;
  final int lossPercent;
  final int jitterMs;
  final int delayMs;
}

@immutable
class NetworkTestResult {
  const NetworkTestResult({
    required this.isComplete,
    required this.roundTripMs,
    required this.uplinkKbps,
    required this.uplinkLossPercent,
    required this.uplinkJitterMs,
    required this.downlinkKbps,
    required this.downlinkLossPercent,
    required this.downlinkJitterMs,
  });

  /// False when Agora couldn't estimate bandwidth (e.g. no network).
  final bool isComplete;
  final int roundTripMs;
  final int uplinkKbps;
  final int uplinkLossPercent;
  final int uplinkJitterMs;
  final int downlinkKbps;
  final int downlinkLossPercent;
  final int downlinkJitterMs;
}
