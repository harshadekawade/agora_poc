import 'dart:convert';
import 'dart:typed_data';

import 'call_session.dart';

/// Messages participants exchange over the call's data channel.
///
/// Demo-grade: any participant could send a "host" message, because nothing
/// verifies the sender. A real release would route host actions through the
/// backend (Agora's ban REST API) or Agora Signaling.
sealed class CallMessage {
  const CallMessage();
}

/// "This is who I am" — sent on join, and again when someone new joins.
final class PresenceMessage extends CallMessage {
  const PresenceMessage({
    required this.name,
    required this.role,
    required this.isHandRaised,
    this.screenShareUid,
  });

  final String name;
  final ParticipantRole role;
  final bool isHandRaised;

  /// Set while this person is sharing their screen as a second uid.
  final int? screenShareUid;
}

final class ChatMessageSent extends CallMessage {
  const ChatMessageSent(this.text);
  final String text;
}

final class HandRaisedMessage extends CallMessage {
  const HandRaisedMessage({required this.isRaised});
  final bool isRaised;
}

/// Host asks [targetUid] to mute. [everyone] targets all participants.
final class MuteRequestMessage extends CallMessage {
  const MuteRequestMessage({required this.targetUid});
  static const everyone = 0;
  final int targetUid;
}

/// Host asks [targetUid] to leave.
final class RemoveRequestMessage extends CallMessage {
  const RemoveRequestMessage({required this.targetUid});
  final int targetUid;
}

/// JSON wire format, versioned so old and new POC builds can coexist.
abstract final class CallMessageCodec {
  static const _version = 1;

  /// Agora's data stream limit per message.
  static const maxBytes = 1024;

  /// 240 characters × 4 bytes (worst-case UTF-8) stays under [maxBytes].
  static const maxChatLength = 240;
  static const maxNameLength = 40;

  static Uint8List encode(CallMessage message) {
    final json = <String, Object?>{
      'v': _version,
      ...switch (message) {
        PresenceMessage(
          :final name,
          :final role,
          :final isHandRaised,
          :final screenShareUid,
        ) =>
          {
            't': 'p',
            'n': _truncate(name, maxNameLength),
            'r': role.name,
            'h': isHandRaised,
            's': ?screenShareUid,
          },
        ChatMessageSent(:final text) => {
          't': 'c',
          'x': _truncate(text, maxChatLength),
        },
        HandRaisedMessage(:final isRaised) => {'t': 'h', 'h': isRaised},
        MuteRequestMessage(:final targetUid) => {'t': 'm', 'u': targetUid},
        RemoveRequestMessage(:final targetUid) => {'t': 'r', 'u': targetUid},
      },
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  /// Returns null for anything malformed or from an unknown version, so a
  /// stray or hostile message can't crash the call.
  static CallMessage? decode(Uint8List bytes) {
    if (bytes.length > maxBytes) return null;
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?> || json['v'] != _version) return null;

    return switch (json['t']) {
      'p' => _decodePresence(json),
      'c' => switch (json['x']) {
        final String text when text.trim().isNotEmpty => ChatMessageSent(
          _truncate(text, maxChatLength),
        ),
        _ => null,
      },
      'h' => switch (json['h']) {
        final bool raised => HandRaisedMessage(isRaised: raised),
        _ => null,
      },
      'm' => switch (json['u']) {
        final int uid => MuteRequestMessage(targetUid: uid),
        _ => null,
      },
      'r' => switch (json['u']) {
        final int uid => RemoveRequestMessage(targetUid: uid),
        _ => null,
      },
      _ => null,
    };
  }

  static PresenceMessage? _decodePresence(Map<String, Object?> json) {
    final name = json['n'];
    final roleName = json['r'];
    final raised = json['h'];
    final shareUid = json['s'];
    if (name is! String || roleName is! String || raised is! bool) return null;
    if (shareUid != null && shareUid is! int) return null;
    final role = ParticipantRole.values.where((r) => r.name == roleName);
    if (role.isEmpty) return null;
    return PresenceMessage(
      name: _truncate(name, maxNameLength),
      role: role.first,
      isHandRaised: raised,
      screenShareUid: shareUid as int?,
    );
  }

  static String _truncate(String text, int maxLength) {
    final runes = text.runes;
    if (runes.length <= maxLength) return text;
    return String.fromCharCodes(runes.take(maxLength));
  }
}
