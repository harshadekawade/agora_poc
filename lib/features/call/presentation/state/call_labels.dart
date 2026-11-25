import '../../../../core/strings/poc_strings.dart';
import '../../domain/call_engine.dart';
import '../../domain/call_session.dart';
import 'call_state.dart';
import 'feature_states.dart';
import 'pre_call_state.dart';

extension CallStatusLabel on CallStatus {
  String get label => switch (this) {
    CallStatus.idle || CallStatus.joining => PocStrings.statusJoining,
    CallStatus.inCall => PocStrings.statusInCall,
    CallStatus.reconnecting => PocStrings.statusReconnecting,
    CallStatus.ended => PocStrings.statusEnded,
    CallStatus.failed => PocStrings.statusFailed,
  };
}

extension CallFailureLabel on CallFailure {
  String get label => switch (this) {
    CallFailure.tokenUnavailable => PocStrings.tokenUnavailable,
    CallFailure.tokenExpired => PocStrings.tokenExpired,
    CallFailure.connectionFailed => PocStrings.connectionFailed,
    CallFailure.tokenRejected => PocStrings.tokenRejected,
    CallFailure.engineError => PocStrings.engineError,
    CallFailure.removedByHost => PocStrings.removedByHost,
  };
}

extension PreCallFailureLabel on PreCallFailure {
  String get label => switch (this) {
    PreCallFailure.notConfigured => PocStrings.notConfigured,
    PreCallFailure.permissionDenied => PocStrings.permissionDenied,
    PreCallFailure.permissionPermanentlyDenied =>
      PocStrings.permissionPermanentlyDenied,
    PreCallFailure.engineError => PocStrings.engineError,
  };
}

extension ParticipantRoleLabel on ParticipantRole {
  String get label => switch (this) {
    ParticipantRole.host => PocStrings.roleHost,
    ParticipantRole.guest => PocStrings.roleGuest,
  };
}

extension CallNetworkQualityLabel on CallNetworkQuality {
  String get label => switch (this) {
    CallNetworkQuality.unknown => 'checking',
    CallNetworkQuality.excellent => 'excellent',
    CallNetworkQuality.good => 'good',
    CallNetworkQuality.poor => 'poor',
    CallNetworkQuality.bad => 'bad',
    CallNetworkQuality.veryBad => 'very bad',
    CallNetworkQuality.down => 'down',
  };

  /// Poor or worse: too weak for smooth video.
  bool get isWeak =>
      this == CallNetworkQuality.poor ||
      this == CallNetworkQuality.bad ||
      this == CallNetworkQuality.veryBad ||
      this == CallNetworkQuality.down;

  /// 0–4 signal bars for the status icon.
  int get bars => switch (this) {
    CallNetworkQuality.excellent => 4,
    CallNetworkQuality.good => 3,
    CallNetworkQuality.poor => 2,
    CallNetworkQuality.bad || CallNetworkQuality.veryBad => 1,
    CallNetworkQuality.down => 0,
    CallNetworkQuality.unknown => 4,
  };
}

extension VideoQualityLabel on VideoQuality {
  String get label => switch (this) {
    VideoQuality.low => 'Low (240p)',
    VideoQuality.standard => 'Standard (360p)',
    VideoQuality.hd => 'HD (720p)',
    VideoQuality.fullHd => 'Full HD (1080p)',
  };

  /// Agora's published per-1,000-minute video price band for this preset.
  String get priceBand => switch (this) {
    VideoQuality.low ||
    VideoQuality.standard ||
    VideoQuality.hd => r'HD band · $3.99 / 1,000 min',
    VideoQuality.fullHd => r'Full HD band · $8.99 / 1,000 min',
  };
}

String formatClock(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// HH:mm for chat timestamps.
String hourMinuteLabel(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

extension CallLogEntryLabel on CallLogEntry {
  /// HH:mm:ss, enough to line events up with what happened on the device.
  String get timeLabel => [
    at.hour,
    at.minute,
    at.second,
  ].map((part) => part.toString().padLeft(2, '0')).join(':');
}

/// Up to two initials for an avatar.
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
}

extension on String {
  Iterable<String> get characters => runes.map(String.fromCharCode);
}
