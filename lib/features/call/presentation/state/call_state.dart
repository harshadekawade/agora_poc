import 'package:flutter/foundation.dart';

import '../../domain/call_engine.dart';
import '../../domain/call_session.dart';

enum CallStatus { idle, joining, inCall, reconnecting, ended, failed }

/// Where everyone else's sound plays: loudspeaker, earpiece, or nowhere.
enum CallAudioOutput { speaker, earpiece, off }

enum CallFailure {
  tokenUnavailable,
  tokenExpired,
  connectionFailed,
  tokenRejected,
  engineError,
  removedByHost,
}

enum CallLayout { grid, speaker }

@immutable
class Participant {
  const Participant({
    required this.uid,
    this.name,
    this.role = ParticipantRole.guest,
    this.isMicOn = true,
    this.videoStatus = RemoteVideoStatus.connecting,
    this.isHandRaised = false,
    this.isFrozenNoticeVisible = false,
  });

  final int uid;

  /// Null until their presence message arrives (web-demo users never send
  /// one).
  final String? name;
  final ParticipantRole role;
  final bool isMicOn;
  final RemoteVideoStatus videoStatus;
  final bool isHandRaised;

  /// Frozen long enough to tell the user (see CallController).
  final bool isFrozenNoticeVisible;

  Participant copyWith({
    String? name,
    ParticipantRole? role,
    bool? isMicOn,
    RemoteVideoStatus? videoStatus,
    bool? isHandRaised,
    bool? isFrozenNoticeVisible,
  }) => Participant(
    uid: uid,
    name: name ?? this.name,
    role: role ?? this.role,
    isMicOn: isMicOn ?? this.isMicOn,
    videoStatus: videoStatus ?? this.videoStatus,
    isHandRaised: isHandRaised ?? this.isHandRaised,
    isFrozenNoticeVisible: isFrozenNoticeVisible ?? this.isFrozenNoticeVisible,
  );
}

@immutable
class CallState {
  const CallState({
    this.status = CallStatus.idle,
    this.session,
    this.participants = const {},
    this.screenShareOwners = const {},
    this.isMicMuted = false,
    this.isCameraOn = true,
    this.isSpeakerOn = true,
    this.isSoundOff = false,
    this.isHandRaised = false,
    this.isScreenSharing = false,
    this.audioRoute,
    this.uplink = CallNetworkQuality.unknown,
    this.downlink = CallNetworkQuality.unknown,
    this.isTokenExpiring = false,
    this.isPipActive = false,
    this.isMinimized = false,
    this.layout = CallLayout.grid,
    this.pinnedUid,
    this.activeSpeakerUid,
    this.pendingMuteRequestFromUid,
    this.failure,
    this.failureDetail,
    this.joinedAt,
    this.isJoinSlow = false,
  });

  final CallStatus status;
  final CallSession? session;

  /// Everyone else in the call, in join order (map literal order is kept).
  /// Includes other people's screen shares, which join as their own uid.
  final Map<int, Participant> participants;

  /// Screen-share uid → the uid of the person sharing.
  final Map<int, int> screenShareOwners;

  final bool isMicMuted;
  final bool isCameraOn;
  final bool isSpeakerOn;

  /// Everyone else's sound is muted on this phone.
  final bool isSoundOff;
  final bool isHandRaised;
  final bool isScreenSharing;
  final String? audioRoute;
  final CallNetworkQuality uplink;
  final CallNetworkQuality downlink;
  final bool isTokenExpiring;

  /// The OS picture-in-picture window is showing.
  final bool isPipActive;

  /// The call is shrunk to the in-app floating window.
  final bool isMinimized;
  final CallLayout layout;
  final int? pinnedUid;
  final int? activeSpeakerUid;

  /// A host asked us to mute; we show a prompt until answered.
  final int? pendingMuteRequestFromUid;
  final CallFailure? failure;
  final String? failureDetail;
  final DateTime? joinedAt;

  /// Still joining after a while, usually because there is no connection.
  final bool isJoinSlow;

  /// Joined (or rejoining) a channel, so video views and controls apply.
  bool get isLive =>
      status == CallStatus.inCall || status == CallStatus.reconnecting;

  /// A join is in progress or done; a second join must be ignored.
  bool get isBusy => isLive || status == CallStatus.joining;

  bool get isHost => session?.isHost ?? false;

  CallAudioOutput get audioOutput => isSoundOff
      ? CallAudioOutput.off
      : isSpeakerOn
      ? CallAudioOutput.speaker
      : CallAudioOutput.earpiece;

  bool isScreenShare(int uid) => screenShareOwners.containsKey(uid);

  /// People only (screen shares excluded), for counts and lists.
  Iterable<Participant> get people =>
      participants.values.where((p) => !isScreenShare(p.uid));

  CallState copyWith({
    CallStatus? status,
    Map<int, Participant>? participants,
    Map<int, int>? screenShareOwners,
    bool? isMicMuted,
    bool? isCameraOn,
    bool? isSpeakerOn,
    bool? isSoundOff,
    bool? isHandRaised,
    bool? isScreenSharing,
    String? audioRoute,
    CallNetworkQuality? uplink,
    CallNetworkQuality? downlink,
    bool? isTokenExpiring,
    bool? isPipActive,
    bool? isMinimized,
    CallLayout? layout,
    ValueGetter<int?>? pinnedUid,
    ValueGetter<int?>? activeSpeakerUid,
    ValueGetter<int?>? pendingMuteRequestFromUid,
    CallFailure? failure,
    String? failureDetail,
    DateTime? joinedAt,
    bool? isJoinSlow,
  }) {
    return CallState(
      status: status ?? this.status,
      session: session,
      participants: participants ?? this.participants,
      screenShareOwners: screenShareOwners ?? this.screenShareOwners,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      isCameraOn: isCameraOn ?? this.isCameraOn,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isSoundOff: isSoundOff ?? this.isSoundOff,
      isHandRaised: isHandRaised ?? this.isHandRaised,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      audioRoute: audioRoute ?? this.audioRoute,
      uplink: uplink ?? this.uplink,
      downlink: downlink ?? this.downlink,
      isTokenExpiring: isTokenExpiring ?? this.isTokenExpiring,
      isPipActive: isPipActive ?? this.isPipActive,
      isMinimized: isMinimized ?? this.isMinimized,
      layout: layout ?? this.layout,
      pinnedUid: pinnedUid != null ? pinnedUid() : this.pinnedUid,
      activeSpeakerUid: activeSpeakerUid != null
          ? activeSpeakerUid()
          : this.activeSpeakerUid,
      pendingMuteRequestFromUid: pendingMuteRequestFromUid != null
          ? pendingMuteRequestFromUid()
          : this.pendingMuteRequestFromUid,
      failure: failure ?? this.failure,
      failureDetail: failureDetail ?? this.failureDetail,
      joinedAt: joinedAt ?? this.joinedAt,
      isJoinSlow: isJoinSlow ?? this.isJoinSlow,
    );
  }
}
