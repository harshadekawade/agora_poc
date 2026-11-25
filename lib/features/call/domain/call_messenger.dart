import 'call_engine.dart';
import 'call_message.dart';

/// Sends typed [CallMessage]s over the raw [CallMessaging] channel.
class CallMessenger {
  const CallMessenger(this._messaging);

  final CallMessaging _messaging;

  Future<void> send(CallMessage message) =>
      _messaging.send(CallMessageCodec.encode(message));

  /// Typed view of a received event, or null if it isn't a valid message.
  static CallMessage? read(DataMessageReceived event) =>
      CallMessageCodec.decode(event.bytes);
}
