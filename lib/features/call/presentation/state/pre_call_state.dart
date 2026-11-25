import 'package:flutter/foundation.dart';

import '../../domain/call_engine.dart';
import '../../domain/call_metrics.dart';
import '../../domain/call_session.dart';

enum PreCallStatus { idle, preparing, ready, failed }

enum PreCallFailure {
  notConfigured,
  permissionDenied,
  permissionPermanentlyDenied,
  engineError,
}

enum EchoTestStatus { idle, starting, running, failed }

enum NetworkTestStatus { idle, running, done, failed }

@immutable
class PreCallState {
  const PreCallState({
    required this.channelId,
    this.status = PreCallStatus.idle,
    this.failure,
    this.failureDetail,
    this.displayName = '',
    this.role = ParticipantRole.guest,
    this.startWithMic = true,
    this.startWithCamera = true,
    this.isEncryptionOn = false,
    this.encryptionPassphrase = '',
    this.echoStatus = EchoTestStatus.idle,
    this.echoError,
    this.networkStatus = NetworkTestStatus.idle,
    this.networkQuality,
    this.networkResult,
  });

  final PreCallStatus status;
  final PreCallFailure? failure;
  final String? failureDetail;
  final String channelId;
  final String displayName;
  final ParticipantRole role;
  final bool startWithMic;
  final bool startWithCamera;
  final bool isEncryptionOn;
  final String encryptionPassphrase;
  final EchoTestStatus echoStatus;
  final String? echoError;
  final NetworkTestStatus networkStatus;
  final CallNetworkQuality? networkQuality;
  final NetworkTestResult? networkResult;

  bool get isReady => status == PreCallStatus.ready;

  /// Encryption on with an empty passphrase would silently join unencrypted.
  bool get canJoin =>
      isReady &&
      channelId.trim().isNotEmpty &&
      (!isEncryptionOn || encryptionPassphrase.isNotEmpty);

  PreCallState copyWith({
    PreCallStatus? status,
    ValueGetter<PreCallFailure?>? failure,
    ValueGetter<String?>? failureDetail,
    String? channelId,
    String? displayName,
    ParticipantRole? role,
    bool? startWithMic,
    bool? startWithCamera,
    bool? isEncryptionOn,
    String? encryptionPassphrase,
    EchoTestStatus? echoStatus,
    ValueGetter<String?>? echoError,
    NetworkTestStatus? networkStatus,
    ValueGetter<CallNetworkQuality?>? networkQuality,
    ValueGetter<NetworkTestResult?>? networkResult,
  }) {
    return PreCallState(
      status: status ?? this.status,
      failure: failure != null ? failure() : this.failure,
      failureDetail: failureDetail != null
          ? failureDetail()
          : this.failureDetail,
      channelId: channelId ?? this.channelId,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      startWithMic: startWithMic ?? this.startWithMic,
      startWithCamera: startWithCamera ?? this.startWithCamera,
      isEncryptionOn: isEncryptionOn ?? this.isEncryptionOn,
      encryptionPassphrase: encryptionPassphrase ?? this.encryptionPassphrase,
      echoStatus: echoStatus ?? this.echoStatus,
      echoError: echoError != null ? echoError() : this.echoError,
      networkStatus: networkStatus ?? this.networkStatus,
      networkQuality: networkQuality != null
          ? networkQuality()
          : this.networkQuality,
      networkResult: networkResult != null
          ? networkResult()
          : this.networkResult,
    );
  }
}
