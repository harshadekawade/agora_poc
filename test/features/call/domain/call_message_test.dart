import 'dart:convert';
import 'dart:typed_data';

import 'package:agora_poc/features/call/domain/call_message.dart';
import 'package:agora_poc/features/call/domain/call_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CallMessage? roundTrip(CallMessage message) =>
      CallMessageCodec.decode(CallMessageCodec.encode(message));

  Uint8List raw(Object json) =>
      Uint8List.fromList(utf8.encode(jsonEncode(json)));

  test('every message type survives encode → decode', () {
    final presence = roundTrip(
      const PresenceMessage(
        name: 'Dr Rao',
        role: ParticipantRole.host,
        isHandRaised: true,
        screenShareUid: 42,
      ),
    );
    expect(presence, isA<PresenceMessage>());
    presence as PresenceMessage;
    expect(presence.name, 'Dr Rao');
    expect(presence.role, ParticipantRole.host);
    expect(presence.isHandRaised, isTrue);
    expect(presence.screenShareUid, 42);

    expect(
      (roundTrip(const ChatMessageSent('hi')) as ChatMessageSent).text,
      'hi',
    );
    expect(
      (roundTrip(const HandRaisedMessage(isRaised: true)) as HandRaisedMessage)
          .isRaised,
      isTrue,
    );
    expect(
      (roundTrip(const MuteRequestMessage(targetUid: 7)) as MuteRequestMessage)
          .targetUid,
      7,
    );
    expect(
      (roundTrip(const RemoveRequestMessage(targetUid: 8))
              as RemoveRequestMessage)
          .targetUid,
      8,
    );
  });

  test('the longest chat in 4-byte characters fits Agora\'s 1 KB limit', () {
    final emoji = '😀' * (CallMessageCodec.maxChatLength + 50);
    final bytes = CallMessageCodec.encode(ChatMessageSent(emoji));

    expect(bytes.length, lessThanOrEqualTo(CallMessageCodec.maxBytes));
    final decoded = CallMessageCodec.decode(bytes) as ChatMessageSent;
    expect(decoded.text.runes.length, CallMessageCodec.maxChatLength);
  });

  test('garbage, wrong versions and bad fields decode to null', () {
    expect(CallMessageCodec.decode(Uint8List.fromList([0xff, 0x00])), isNull);
    expect(CallMessageCodec.decode(raw({'v': 2, 't': 'c', 'x': 'hi'})), isNull);
    expect(CallMessageCodec.decode(raw({'v': 1, 't': 'zz'})), isNull);
    expect(CallMessageCodec.decode(raw({'v': 1, 't': 'm', 'u': 'x'})), isNull);
    expect(CallMessageCodec.decode(raw({'v': 1, 't': 'c', 'x': '  '})), isNull);
    expect(
      CallMessageCodec.decode(
        raw({'v': 1, 't': 'p', 'n': 'A', 'r': 'admin', 'h': false}),
      ),
      isNull,
    );
    expect(CallMessageCodec.decode(raw([1, 2, 3])), isNull);
  });
}
