import 'package:flutter/foundation.dart';

enum ParticipantRole { host, guest }

/// Who is joining which call, decided on the pre-call screen.
@immutable
class CallSession {
  const CallSession({
    required this.channelId,
    required this.localUid,
    required this.screenShareUid,
    required this.displayName,
    required this.role,
    required this.startWithMic,
    required this.startWithCamera,
    required this.encryptionPassphrase,
  });

  final String channelId;
  final int localUid;

  /// Second identity used only while sharing the screen.
  final int screenShareUid;
  final String displayName;
  final ParticipantRole role;
  final bool startWithMic;
  final bool startWithCamera;

  /// Empty means no encryption.
  final String encryptionPassphrase;

  bool get isHost => role == ParticipantRole.host;
  bool get isEncrypted => encryptionPassphrase.isNotEmpty;
}
