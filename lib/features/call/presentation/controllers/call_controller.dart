import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strings/poc_strings.dart';
import '../../domain/call_engine.dart';
import '../../domain/call_keep_alive.dart';
import '../../domain/call_message.dart';
import '../../domain/call_messenger.dart';
import '../../domain/call_session.dart';
import '../../domain/pip_service.dart';
import '../../domain/token_provider.dart';
import '../layout/call_layout_planner.dart';
import '../providers/call_providers.dart';
import '../state/call_state.dart';

/// Owns one call: join → participants, controls and host actions → leave.
///
/// Chat, stats, speaking levels, capture and media settings live in their
/// own controllers so each has one reason to change.
class CallController extends Notifier<CallState> {
  /// Batches presence replies when several people join at once.
  static const _presenceResendDelay = Duration(milliseconds: 400);

  late CallEngine _engine;
  late MediaEffects _effects;
  late CallCapture _capture;
  late PipService _pip;
  late TokenProvider _tokens;
  late CallMessenger _messenger;
  late CallKeepAlive _keepAlive;

  late Duration _frozenNoticeDelay;
  late Duration _noVideoTimeout;
  late Duration _slowJoinNoticeDelay;
  late Duration _presenceHeartbeat;
  late Duration _presenceFollowUp;

  /// Fires if a join takes long enough to suggest there is no connection.
  Timer? _slowJoinTimer;

  bool _isPipSupported = false;
  Timer? _presenceTimer;
  Timer? _presenceFollowUpTimer;

  /// Re-announces who we are while live. Data messages can be lost (e.g.
  /// during a reconnect right after joining); a lost one would leave others
  /// without our name and role, so a doctor's host actions were ignored.
  Timer? _presenceHeartbeatTimer;

  /// Share requested; waiting for the OS permission dialog and capture.
  bool _isStartingShare = false;

  /// PiP just ended; the next lifecycle change says whether the user
  /// expanded it (resumed) or closed it (stopped).
  bool _isPipExitPending = false;
  AppLifecycleState? _lifecycle;

  /// Last stream quality requested per remote uid, to avoid repeat calls.
  final Map<int, bool> _streamQuality = {};

  /// Pending "show the frozen notice" timers and freeze start times.
  final Map<int, Timer> _frozenTimers = {};
  final Map<int, DateTime> _frozenSince = {};

  /// Per new participant: fires if Agora says nothing about their video.
  final Map<int, Timer> _noVideoTimers = {};

  /// True when we switched to speaker view because someone started sharing,
  /// so we know to switch back when they stop.
  bool _didAutoSwitchForShare = false;

  @override
  CallState build() {
    _engine = ref.watch(callEngineProvider);
    _effects = ref.watch(mediaEffectsProvider);
    _capture = ref.watch(callCaptureProvider);
    _pip = ref.watch(pipServiceProvider);
    _tokens = ref.watch(tokenProviderProvider);
    _messenger = ref.watch(callMessengerProvider);
    _frozenNoticeDelay = ref.watch(frozenNoticeDelayProvider);
    _noVideoTimeout = ref.watch(noVideoTimeoutProvider);
    _slowJoinNoticeDelay = ref.watch(slowJoinNoticeDelayProvider);
    _presenceHeartbeat = ref.watch(presenceHeartbeatProvider);
    _presenceFollowUp = ref.watch(presenceFollowUpProvider);
    _keepAlive = ref.watch(callKeepAliveProvider);

    final engineEvents = _engine.events.listen(_onEngineEvent);
    final pipEvents = _pip.statusChanges.listen(_onPipStatus);
    // One place starts and stops what lasts exactly as long as the call is
    // live, whichever path makes it live or ends it (leave, failure,
    // removal, PiP closed).
    listenSelf(_onLiveChanged);
    ref.onDispose(() {
      engineEvents.cancel();
      pipEvents.cancel();
      _presenceTimer?.cancel();
      _presenceFollowUpTimer?.cancel();
      _presenceHeartbeatTimer?.cancel();
      _slowJoinTimer?.cancel();
      _cancelFrozenTimers();
    });
    return const CallState();
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// The engine must already be initialized (the pre-call screen does it).
  Future<void> join(CallSession session) async {
    if (state.isBusy) return;
    _streamQuality.clear();
    state = CallState(
      status: CallStatus.joining,
      session: session,
      isMicMuted: !session.startWithMic,
      isCameraOn: session.startWithCamera,
    );
    _log(
      'Joining "${session.channelId}" as ${session.displayName} '
      '(${session.role.name}, uid ${session.localUid})'
      '${session.isEncrypted ? ', encrypted' : ''}',
    );
    _startSlowJoinTimer(session);

    try {
      final token = await _tokens.rtcToken(
        channelId: session.channelId,
        uid: session.localUid,
      );
      if (!_isStillJoining(session)) return;
      await _effects.setEncryption(
        passphrase: session.encryptionPassphrase,
        channelId: session.channelId,
      );
      await _engine.setMicMuted(!session.startWithMic);
      await _engine.setCameraEnabled(session.startWithCamera);
      // "Sound off" from a previous call must not carry over.
      await _engine.setOthersMuted(false);
      if (!_isStillJoining(session)) return;
      await _engine.join(
        channelId: session.channelId,
        token: token,
        uid: session.localUid,
      );
      // Cancelled while the join was being sent: Agora may have run our
      // leave first, so leave again or we'd sit in the room unseen.
      if (!_isStillJoining(session)) await _leaveCancelledJoin();
    } on TokenUnavailableException catch (error) {
      if (!ref.mounted) return;
      _fail(CallFailure.tokenUnavailable, detail: error.message);
    } catch (error) {
      if (!ref.mounted) return;
      _fail(CallFailure.engineError, detail: '$error');
    }
  }

  /// Agora keeps retrying a join with no network and reports nothing, so
  /// after a while tell the user and let them cancel.
  void _startSlowJoinTimer(CallSession session) {
    _slowJoinTimer?.cancel();
    _slowJoinTimer = Timer(_slowJoinNoticeDelay, () {
      if (!_isStillJoining(session)) return;
      _log(
        'Still joining after ${_slowJoinNoticeDelay.inSeconds} s '
        '→ showing "no connection" notice',
      );
      state = state.copyWith(isJoinSlow: true);
    });
  }

  /// False once the user left (or cancelled) or another join started.
  bool _isStillJoining(CallSession session) =>
      ref.mounted &&
      state.status == CallStatus.joining &&
      identical(state.session, session);

  Future<void> _leaveCancelledJoin() async {
    _log('Join was cancelled → leaving');
    try {
      await _engine.leave();
    } catch (error) {
      _log('Leave error: $error');
    }
  }

  /// Also cancels a join that is still in progress.
  Future<void> leave() async {
    if (!state.isBusy) return;
    _log(state.isLive ? 'Leaving' : 'Cancelling join');
    await _leaveQuietly();
    if (!ref.mounted) return;
    state = state.copyWith(
      status: CallStatus.ended,
      participants: const {},
      screenShareOwners: const {},
      isPipActive: false,
      isMinimized: false,
      isScreenSharing: false,
      isJoinSlow: false,
    );
  }

  // ── Local controls ───────────────────────────────────────────────────────

  Future<void> toggleMic() => _applyControl(
    label: 'Mic muted',
    action: () => _engine.setMicMuted(!state.isMicMuted),
    next: () => state.copyWith(isMicMuted: !state.isMicMuted),
    describe: (next) => '${next.isMicMuted}',
  );

  Future<void> toggleCamera() => _applyControl(
    label: 'Camera on',
    action: () => _engine.setCameraEnabled(!state.isCameraOn),
    next: () => state.copyWith(isCameraOn: !state.isCameraOn),
    describe: (next) => '${next.isCameraOn}',
  );

  /// "Off" mutes everyone else on this phone; picking speaker or earpiece
  /// turns their sound back on.
  Future<void> setAudioOutput(CallAudioOutput output) {
    final isSoundOff = output == CallAudioOutput.off;
    // While sound is off, keep the last route so turning it on restores it.
    final isSpeakerOn = isSoundOff
        ? state.isSpeakerOn
        : output == CallAudioOutput.speaker;
    return _applyControl(
      label: 'Audio output',
      action: () async {
        if (isSoundOff != state.isSoundOff) {
          await _engine.setOthersMuted(isSoundOff);
        }
        if (isSpeakerOn != state.isSpeakerOn) {
          await _engine.setSpeakerOn(isSpeakerOn);
        }
      },
      next: () =>
          state.copyWith(isSoundOff: isSoundOff, isSpeakerOn: isSpeakerOn),
      describe: (next) => next.audioOutput.name,
    );
  }

  /// Logged so the Android camera-switch freeze (GitHub #2432) shows up as
  /// "Switched camera" followed by a "frozen" video event on other devices.
  Future<void> switchCamera() => _applyControl(
    label: 'Switched camera',
    action: _engine.switchCamera,
    next: () => state,
    describe: (_) => 'ok',
  );

  Future<void> toggleHand() async {
    if (!state.isLive) return;
    final raised = !state.isHandRaised;
    try {
      await _messenger.send(HandRaisedMessage(isRaised: raised));
      if (!ref.mounted) return;
      state = state.copyWith(isHandRaised: raised);
      _log(raised ? 'Raised hand' : 'Lowered hand');
    } catch (error) {
      _log('Raise hand failed: $error');
    }
  }

  Future<void> toggleScreenShare() async {
    final session = state.session;
    if (!state.isLive || session == null) return;
    if (!_capture.isScreenShareSupported) {
      _log('Screen sharing is not available on this platform in the POC');
      return;
    }
    try {
      if (state.isScreenSharing) {
        _log('Stopping screen share');
        await _capture.stopScreenShare();
        if (!ref.mounted) return;
        state = state.copyWith(isScreenSharing: false);
        unawaited(_sendPresence());
        return;
      }
      _log('Starting screen share (uid ${session.screenShareUid})');
      // Android's "start recording?" dialog would otherwise count as leaving
      // the app and throw the call into PiP, losing the dialog.
      _isStartingShare = true;
      await _configurePip();
      final token = await _tokens.rtcToken(
        channelId: session.channelId,
        uid: session.screenShareUid,
      );
      await _capture.startScreenShare(
        channelId: session.channelId,
        shareUid: session.screenShareUid,
        token: token,
      );
    } catch (error) {
      _log('Screen share error: $error');
      _isStartingShare = false;
      unawaited(_configurePip());
    }
  }

  /// No automatic PiP while Android's share-permission dialog is up: it
  /// makes the app inactive, and PiP would hide the dialog. Once sharing,
  /// PiP is allowed so the sharer can keep the call in view (the PiP
  /// window is then part of the shared screen too).
  bool get _isPipBlockedByShare => _isStartingShare;

  // ── Layout & navigation ──────────────────────────────────────────────────

  void setLayout(CallLayout layout) {
    if (state.layout == layout) return;
    // The user chose a layout; don't switch it back automatically later.
    _didAutoSwitchForShare = false;
    state = state.copyWith(layout: layout);
    _log('Layout: ${layout.name}');
    _applyStreamQualities();
  }

  void togglePin(int uid) {
    final next = state.pinnedUid == uid ? null : uid;
    state = state.copyWith(
      pinnedUid: () => next,
      layout: next == null ? null : CallLayout.speaker,
    );
    _log(next == null ? 'Unpinned' : 'Pinned uid $uid');
    _applyStreamQualities();
    unawaited(_configurePip());
  }

  /// Shrinks the call to the in-app floating window (or restores it).
  void setMinimized(bool minimized) {
    if (state.isMinimized == minimized) return;
    state = state.copyWith(isMinimized: minimized);
  }

  // ── Host actions (demo-grade: see CallMessage) ───────────────────────────

  Future<void> requestMute(int uid) =>
      _sendHostAction(MuteRequestMessage(targetUid: uid), 'Asked $uid to mute');

  Future<void> requestMuteEveryone() => _sendHostAction(
    const MuteRequestMessage(targetUid: MuteRequestMessage.everyone),
    'Asked everyone to mute',
  );

  Future<void> requestRemove(int uid) => _sendHostAction(
    RemoveRequestMessage(targetUid: uid),
    'Asked $uid to leave',
  );

  Future<void> acceptMuteRequest() async {
    state = state.copyWith(pendingMuteRequestFromUid: () => null);
    if (state.isMicMuted) return;
    await toggleMic();
  }

  void dismissMuteRequest() {
    state = state.copyWith(pendingMuteRequestFromUid: () => null);
    _log('Ignored mute request');
  }

  // ── App lifecycle (system PiP) ───────────────────────────────────────────

  /// System PiP is driven by app lifecycle, as in Agora's own example.
  Future<void> onAppLifecycleChanged(AppLifecycleState lifecycle) async {
    _lifecycle = lifecycle;
    if (!state.isLive || !_isPipSupported) return;
    if (_isPipExitPending) {
      _isPipExitPending = false;
      if (_isClosed(lifecycle)) {
        await _leaveAfterPipClosed();
        return;
      }
    }
    try {
      switch (lifecycle) {
        case AppLifecycleState.inactive:
          if (_isPipBlockedByShare) return;
          _log('App inactive → PiP enter');
          await _pip.enterOnBackground();
        case AppLifecycleState.resumed:
          await _pip.exitOnForeground();
        case AppLifecycleState.paused ||
            AppLifecycleState.hidden ||
            AppLifecycleState.detached:
          break;
      }
    } catch (error) {
      _log('PiP lifecycle error: $error');
    }
  }

  // ── Engine events ────────────────────────────────────────────────────────

  void _onEngineEvent(CallEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case CallJoined(:final localUid, :final elapsedMs):
        // A join that was cancelled can still report success. Leave it
        // rather than show it as a live call.
        if (state.status != CallStatus.joining) {
          unawaited(_leaveCancelledJoin());
          return;
        }
        _log('Joined as uid $localUid in $elapsedMs ms');
        _slowJoinTimer?.cancel();
        state = state.copyWith(
          status: CallStatus.inCall,
          joinedAt: DateTime.now(),
          isJoinSlow: false,
        );
        unawaited(_sendPresence());
        _schedulePresence();
        unawaited(_preparePip());
      case CallLeft():
        _log('Left channel');
      case RemoteUserJoined(:final uid):
        _log('uid $uid joined');
        _upsertParticipant(uid, (p) => p);
        _startNoVideoTimer(uid);
        _schedulePresence();
        _onParticipantsChanged();
      case RemoteUserLeft(:final uid, :final reason):
        _log('${_nameOf(uid)} left ($reason)');
        _removeParticipant(uid);
        _onParticipantsChanged();
      case RemoteVideoChanged(:final uid, :final status):
        _onRemoteVideoChanged(uid, status);
      case RemoteAudioMuted(:final uid, :final muted):
        _log('${_nameOf(uid)} mic ${muted ? 'muted' : 'on'}');
        _upsertParticipant(uid, (p) => p.copyWith(isMicOn: !muted));
      case ConnectionChanged(
        state: final connection,
        :final reason,
        :final isTokenRejected,
      ):
        _onConnectionChanged(connection, reason, isTokenRejected);
      case NetworkQualityChanged(:final uplink, :final downlink):
        _onNetworkQuality(uplink, downlink);
      case TokenWillExpire(:final localUid):
        unawaited(_renewToken(localUid, isExpired: false));
      case TokenExpired(:final localUid):
        unawaited(_renewToken(localUid, isExpired: true));
      case AudioRouteChanged(:final route):
        _log('Audio route: $route');
        state = state.copyWith(audioRoute: route);
      case CallErrorOccurred(:final code, :final message):
        _log('Engine error $code: $message');
      case ActiveSpeakerChanged(:final uid):
        if (state.activeSpeakerUid == uid) return;
        state = state.copyWith(activeSpeakerUid: () => uid);
        if (state.layout == CallLayout.speaker) _applyStreamQualities();
      case DataMessageReceived(:final fromUid):
        _onMessage(fromUid, CallMessenger.read(event));
      case ScreenShareStateChanged(:final status, :final detail):
        _onScreenShareChanged(status, detail);
      case VolumesUpdated() ||
          CallStatsUpdated() ||
          LocalVideoStatsUpdated() ||
          RemoteVideoStatsUpdated() ||
          RemoteAudioStatsUpdated() ||
          SnapshotTaken() ||
          RecordingStateChanged() ||
          RecordingProgress() ||
          NetworkTestQuality() ||
          NetworkTestCompleted():
        // Handled by the speaking, stats, capture and pre-call controllers.
        break;
    }
  }

  void _onConnectionChanged(
    CallConnectionState connection,
    String reason,
    bool isTokenRejected,
  ) {
    _log('Connection: ${connection.name} ($reason)');
    switch (connection) {
      case CallConnectionState.reconnecting when state.isLive:
        state = state.copyWith(status: CallStatus.reconnecting);
      case CallConnectionState.connected
          when state.status == CallStatus.reconnecting:
        state = state.copyWith(status: CallStatus.inCall);
        // Messages sent while reconnecting may be lost: announce again.
        _schedulePresence();
      case CallConnectionState.failed:
        // The vendor's reason is already in the log; the screen gets words.
        _fail(
          isTokenRejected
              ? CallFailure.tokenRejected
              : CallFailure.connectionFailed,
        );
        unawaited(_leaveQuietly());
      default:
        break;
    }
  }

  /// Quality arrives every ~2 s; log only changes so the log stays readable.
  void _onNetworkQuality(
    CallNetworkQuality uplink,
    CallNetworkQuality downlink,
  ) {
    if (uplink == state.uplink && downlink == state.downlink) return;
    _log('Network up ${uplink.name} / down ${downlink.name}');
    state = state.copyWith(uplink: uplink, downlink: downlink);
  }

  /// Short freezes are normal: network jitter, high/low stream switches, and
  /// a still shared screen sends almost no frames. So the "frozen" notice
  /// appears only after [_frozenNoticeDelay], and never for screen shares.
  /// Every freeze is still logged with its length.
  void _onRemoteVideoChanged(int uid, RemoteVideoStatus status) {
    // Any video news, even "starting" on a slow network, means Agora is
    // tracking their video, so the no-video fallback is no longer needed.
    _noVideoTimers.remove(uid)?.cancel();
    final previous = state.participants[uid]?.videoStatus;
    if (status == RemoteVideoStatus.frozen) {
      _frozenSince[uid] ??= DateTime.now();
      _frozenTimers.remove(uid)?.cancel();
      if (!state.isScreenShare(uid)) {
        _frozenTimers[uid] = Timer(
          _frozenNoticeDelay,
          () => _showFrozenNotice(uid),
        );
      }
    } else {
      _frozenTimers.remove(uid)?.cancel();
      final since = _frozenSince.remove(uid);
      if (since != null) {
        final frozenMs = DateTime.now().difference(since).inMilliseconds;
        _log('${_nameOf(uid)} video was frozen for $frozenMs ms');
      }
    }
    if (previous != status) _log('${_nameOf(uid)} video: ${status.name}');
    _upsertParticipant(
      uid,
      (p) => p.copyWith(
        videoStatus: status,
        isFrozenNoticeVisible: status == RemoteVideoStatus.frozen
            ? p.isFrozenNoticeVisible
            : false,
      ),
    );
  }

  void _showFrozenNotice(int uid) {
    _frozenTimers.remove(uid);
    if (!ref.mounted) return;
    final participant = state.participants[uid];
    if (participant?.videoStatus != RemoteVideoStatus.frozen) return;
    _log('${_nameOf(uid)} video still frozen → showing notice');
    _upsertParticipant(uid, (p) => p.copyWith(isFrozenNoticeVisible: true));
  }

  void _cancelFrozenTimers() {
    for (final timer in [..._frozenTimers.values, ..._noVideoTimers.values]) {
      timer.cancel();
    }
    _frozenTimers.clear();
    _frozenSince.clear();
    _noVideoTimers.clear();
  }

  /// Someone who joins with no camera (blocked, off, or a browser without
  /// one) gets no video event at all from Agora, so without this their tile
  /// would say "Connecting video…" forever.
  void _startNoVideoTimer(int uid) {
    _noVideoTimers.remove(uid)?.cancel();
    _noVideoTimers[uid] = Timer(_noVideoTimeout, () {
      _noVideoTimers.remove(uid);
      if (!ref.mounted) return;
      final participant = state.participants[uid];
      if (participant?.videoStatus != RemoteVideoStatus.connecting) return;
      _log('${_nameOf(uid)} sent no video → showing as camera off');
      _upsertParticipant(
        uid,
        (p) => p.copyWith(videoStatus: RemoteVideoStatus.off),
      );
    });
  }

  void _onScreenShareChanged(ScreenShareStatus status, String? detail) {
    _log('Screen share ${status.name} ($detail)');
    final wasStarting = _isStartingShare;
    _isStartingShare = false;
    final isSharing = status == ScreenShareStatus.active;
    // Failed or cancelled (e.g. the permission dialog was declined) before
    // it ever started: leave the screen connection, or it lingers in the
    // room and blocks the next try.
    if (!isSharing) {
      unawaited(_capture.stopScreenShare().catchError((_) {}));
    }
    if (state.isScreenSharing != isSharing) {
      state = state.copyWith(isScreenSharing: isSharing);
      unawaited(_sendPresence());
      unawaited(_setCameraQualityForSharing(isSharing));
    }
    if (wasStarting || !isSharing) unawaited(_configurePip());
  }

  /// Camera and screen share one upload. On a slow connection the screen
  /// matters more, so the camera drops to Low while sharing and returns to
  /// the user's chosen quality afterwards.
  Future<void> _setCameraQualityForSharing(bool isSharing) async {
    final quality = isSharing
        ? VideoQuality.low
        : ref.read(mediaSettingsControllerProvider).quality;
    try {
      await _effects.setVideoQuality(quality);
      _log(
        'Camera quality ${isSharing ? 'lowered' : 'restored'}: '
        '${quality.name}',
      );
    } catch (error) {
      _log('Camera quality change failed: $error');
    }
  }

  /// A shared screen is unreadable as a grid tile, so switch to speaker view
  /// (the screen becomes the main tile).
  void _onRemoteShareStarted(int ownerUid) {
    _log('${_nameOf(ownerUid)} started sharing their screen');
    if (state.layout != CallLayout.grid) return;
    _didAutoSwitchForShare = true;
    state = state.copyWith(layout: CallLayout.speaker);
  }

  /// Back to grid once every share has ended, unless the user picked a
  /// layout or pinned someone in the meantime.
  void _restoreLayoutIfSharesEnded() {
    if (!_didAutoSwitchForShare || state.screenShareOwners.isNotEmpty) return;
    _didAutoSwitchForShare = false;
    if (state.layout == CallLayout.speaker && state.pinnedUid == null) {
      state = state.copyWith(layout: CallLayout.grid);
    }
  }

  // ── Messages from other participants ─────────────────────────────────────

  void _onMessage(int fromUid, CallMessage? message) {
    final myUid = state.session?.localUid;
    switch (message) {
      case null:
        _log('Ignored a malformed message from uid $fromUid');
      case PresenceMessage(
        :final name,
        :final role,
        :final isHandRaised,
        :final screenShareUid,
      ):
        _upsertParticipant(
          fromUid,
          (p) => p.copyWith(name: name, role: role, isHandRaised: isHandRaised),
        );
        final isNewShare =
            screenShareUid != null &&
            !state.screenShareOwners.containsKey(screenShareUid);
        state = state.copyWith(
          screenShareOwners: {
            for (final entry in state.screenShareOwners.entries)
              if (entry.value != fromUid) entry.key: entry.value,
            ?screenShareUid: fromUid,
          },
        );
        if (isNewShare) {
          _onRemoteShareStarted(fromUid);
        } else if (screenShareUid == null) {
          _restoreLayoutIfSharesEnded();
        }
        _onParticipantsChanged();
      case HandRaisedMessage(:final isRaised):
        _log('${_nameOf(fromUid)} ${isRaised ? 'raised' : 'lowered'} hand');
        _upsertParticipant(fromUid, (p) => p.copyWith(isHandRaised: isRaised));
      case MuteRequestMessage(:final targetUid):
        if (!_isFromHost(fromUid)) return;
        final isForMe =
            targetUid == myUid || targetUid == MuteRequestMessage.everyone;
        if (!isForMe || state.isMicMuted) return;
        _log('${_nameOf(fromUid)} asked you to mute');
        state = state.copyWith(pendingMuteRequestFromUid: () => fromUid);
      case RemoveRequestMessage(:final targetUid):
        if (!_isFromHost(fromUid) || targetUid != myUid) return;
        _log('${_nameOf(fromUid)} removed you from the call');
        unawaited(_leaveQuietly());
        _fail(CallFailure.removedByHost);
      case ChatMessageSent():
        // Chat is handled by ChatController.
        break;
    }
  }

  bool _isFromHost(int uid) {
    final isHost = state.participants[uid]?.role == ParticipantRole.host;
    if (!isHost) _log('Ignored host action from non-host uid $uid');
    return isHost;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _nameOf(int uid) => state.participants[uid]?.name ?? 'uid $uid';

  void _upsertParticipant(
    int uid,
    Participant Function(Participant current) update,
  ) {
    final current = state.participants[uid] ?? Participant(uid: uid);
    state = state.copyWith(
      participants: {...state.participants, uid: update(current)},
    );
  }

  void _removeParticipant(int uid) {
    state = state.copyWith(
      participants: Map.of(state.participants)..remove(uid),
      screenShareOwners: {
        for (final entry in state.screenShareOwners.entries)
          if (entry.key != uid && entry.value != uid) entry.key: entry.value,
      },
      pinnedUid: state.pinnedUid == uid ? () => null : null,
      activeSpeakerUid: state.activeSpeakerUid == uid ? () => null : null,
    );
    _streamQuality.remove(uid);
    _frozenTimers.remove(uid)?.cancel();
    _frozenSince.remove(uid);
    _noVideoTimers.remove(uid)?.cancel();
    _restoreLayoutIfSharesEnded();
  }

  void _onParticipantsChanged() {
    _applyStreamQualities();
    unawaited(_configurePip());
  }

  /// Requests the full-quality stream only for big tiles (see planner).
  void _applyStreamQualities() {
    final high = CallLayoutPlanner.highQualityUids(state);
    for (final uid in state.participants.keys) {
      final wantsHigh = high.contains(uid);
      if (_streamQuality[uid] == wantsHigh) continue;
      _streamQuality[uid] = wantsHigh;
      unawaited(
        _engine
            .setRemoteVideoHighQuality(uid: uid, high: wantsHigh)
            .catchError((Object e) => _log('Stream quality error: $e')),
      );
    }
  }

  /// Announces soon, and once more a little later: on device the first
  /// messages around a join were usually lost.
  void _schedulePresence() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer(_presenceResendDelay, _sendPresence);
    _presenceFollowUpTimer?.cancel();
    _presenceFollowUpTimer = Timer(_presenceFollowUp, _sendPresence);
  }

  Future<void> _sendPresence() async {
    final session = state.session;
    if (session == null || !state.isLive) return;
    try {
      await _messenger.send(
        PresenceMessage(
          name: session.displayName,
          role: session.role,
          isHandRaised: state.isHandRaised,
          screenShareUid: state.isScreenSharing ? session.screenShareUid : null,
        ),
      );
    } catch (error) {
      _log('Presence send failed: $error');
    }
  }

  Future<void> _sendHostAction(CallMessage message, String logText) async {
    if (!state.isLive || !state.isHost) return;
    try {
      await _messenger.send(message);
      _log(logText);
    } catch (error) {
      _log('Host action failed: $error');
    }
  }

  Future<void> _renewToken(int forUid, {required bool isExpired}) async {
    final session = state.session;
    if (session == null) return;
    final isScreen = forUid == session.screenShareUid;
    final which = isScreen ? 'screen' : 'call';
    _log('Token ${isExpired ? 'expired' : 'expiring'} ($which) → renewing');
    if (!isScreen) state = state.copyWith(isTokenExpiring: true);
    try {
      final token = await _tokens.rtcToken(
        channelId: session.channelId,
        uid: forUid,
      );
      if (isScreen) {
        await _capture.renewScreenShareToken(token);
      } else {
        await _engine.renewToken(token);
      }
      if (!ref.mounted) return;
      _log('Token renewed ($which)');
      if (!isScreen) state = state.copyWith(isTokenExpiring: false);
    } catch (error) {
      if (!ref.mounted) return;
      _log('Token renewal failed ($which): $error');
      if (isExpired && !isScreen) {
        _fail(CallFailure.tokenExpired);
        unawaited(_leaveQuietly());
      }
    }
  }

  static bool _isClosed(AppLifecycleState? lifecycle) =>
      lifecycle == AppLifecycleState.paused ||
      lifecycle == AppLifecycleState.hidden ||
      lifecycle == AppLifecycleState.detached;

  /// Closing the PiP window (its X, or swiping it away) ends the call, as in
  /// Meet and Zoom. Leaving now, while the app still runs, tells the others
  /// at once; otherwise Agora only drops us after ~20 s of silence.
  Future<void> _leaveAfterPipClosed() async {
    _log('PiP window closed → leaving the call');
    await leave();
  }

  void _onPipStatus(PipStatus status) {
    if (!ref.mounted) return;
    _log('PiP ${status.name}');
    final wasPipActive = state.isPipActive;
    state = state.copyWith(isPipActive: status == PipStatus.active);
    if (wasPipActive && status == PipStatus.inactive && state.isLive) {
      // Expanding resumes the app; closing stops it. The lifecycle change
      // may arrive before or after this event, so handle both orders.
      if (_isClosed(_lifecycle)) {
        unawaited(_leaveAfterPipClosed());
      } else {
        _isPipExitPending = true;
      }
    }
    if (status == PipStatus.failed) {
      // Agora's example disposes the controller after a failure.
      _isPipSupported = false;
      unawaited(_pip.release());
    }
  }

  Future<void> _preparePip() async {
    try {
      _isPipSupported = await _pip.prepare();
      _log('System PiP supported: $_isPipSupported');
      await _configurePip();
    } catch (error) {
      _isPipSupported = false;
      _log('PiP setup error: $error');
    }
  }

  /// iOS PiP shows one stream: the main speaker-view tile.
  Future<void> _configurePip() async {
    final session = state.session;
    if (!_isPipSupported || session == null || !state.isLive) return;
    final main = CallLayoutPlanner.mainTile(state);
    try {
      await _pip.configure(
        channelId: session.channelId,
        localUid: session.localUid,
        remoteUids: main.isLocal ? const [] : [main.uid],
        isAutoEnterAllowed: !_isPipBlockedByShare,
      );
    } catch (error) {
      _log('PiP configure error: $error');
    }
  }

  Future<void> _leaveQuietly() async {
    _presenceTimer?.cancel();
    _presenceFollowUpTimer?.cancel();
    _slowJoinTimer?.cancel();
    _cancelFrozenTimers();
    _didAutoSwitchForShare = false;
    _isStartingShare = false;
    _isPipExitPending = false;
    // Always, not only when sharing: a half-started share is also in the
    // room, and would linger as a frozen tile on other phones for ~20 s.
    try {
      await _capture.stopScreenShare();
    } catch (error) {
      _log('Screen share stop error: $error');
    }
    if (state.isScreenSharing) {
      // The camera was lowered for sharing; the next call starts normal.
      await _setCameraQualityForSharing(false);
    }
    try {
      await _engine.leave();
    } catch (error) {
      _log('Leave error: $error');
    }
    try {
      _isPipSupported = false;
      await _pip.release();
    } catch (error) {
      _log('PiP release error: $error');
    }
  }

  /// Runs a control, updating state only if the engine call succeeded.
  Future<void> _applyControl({
    required String label,
    required Future<void> Function() action,
    required CallState Function() next,
    required String Function(CallState next) describe,
  }) async {
    if (!state.isLive) return;
    try {
      final nextState = next();
      await action();
      if (!ref.mounted) return;
      state = nextState;
      _log('$label: ${describe(nextState)}');
    } catch (error) {
      if (!ref.mounted) return;
      _log('$label failed: $error');
    }
  }

  void _fail(CallFailure failure, {String? detail}) {
    _log('Failed: ${failure.name}${detail == null ? '' : ' ($detail)'}');
    _slowJoinTimer?.cancel();
    state = state.copyWith(
      status: CallStatus.failed,
      failure: failure,
      failureDetail: detail,
      isMinimized: false,
      isJoinSlow: false,
    );
  }

  // ── Ongoing-call service ─────────────────────────────────────────────────

  void _onLiveChanged(CallState? previous, CallState next) {
    final wasLive = previous?.isLive ?? false;
    if (wasLive == next.isLive) return;
    _presenceHeartbeatTimer?.cancel();
    if (next.isLive) {
      _presenceHeartbeatTimer = Timer.periodic(
        _presenceHeartbeat,
        (_) => unawaited(_sendPresence()),
      );
    }
    unawaited(next.isLive ? _startKeepAlive() : _stopKeepAlive());
  }

  Future<void> _startKeepAlive() async {
    try {
      await _keepAlive.start(
        title: PocStrings.ongoingCallTitle,
        text: PocStrings.ongoingCallText,
      );
      _log('Ongoing-call service started');
    } catch (error) {
      // The call still works in the foreground; only background audio and
      // video are at risk.
      _log('Ongoing-call service failed: $error');
    }
  }

  Future<void> _stopKeepAlive() async {
    try {
      await _keepAlive.stop();
      _log('Ongoing-call service stopped');
    } catch (error) {
      _log('Ongoing-call service stop error: $error');
    }
  }

  void _log(String message) {
    if (!ref.mounted) return;
    ref.read(callLogProvider.notifier).add(message);
  }
}
