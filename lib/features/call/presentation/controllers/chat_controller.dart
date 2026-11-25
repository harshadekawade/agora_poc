import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/call_engine.dart';
import '../../domain/call_message.dart';
import '../../domain/call_messenger.dart';
import '../providers/call_providers.dart';
import '../state/feature_states.dart';

/// In-call text chat over the data channel. Messages exist only for the
/// call: no history, nothing stored by Agora.
class ChatController extends Notifier<ChatState> {
  late CallMessenger _messenger;

  @override
  ChatState build() {
    _messenger = ref.watch(callMessengerProvider);
    final events = ref.watch(callEngineProvider).events.listen(_onEvent);
    ref.onDispose(events.cancel);
    return const ChatState();
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    try {
      await _messenger.send(ChatMessageSent(trimmed));
      if (!ref.mounted) return;
      state = state.copyWith(
        sendError: () => null,
        entries: [
          ...state.entries,
          ChatEntry(
            fromUid: 0,
            text: trimmed.length > CallMessageCodec.maxChatLength
                ? trimmed.substring(0, CallMessageCodec.maxChatLength)
                : trimmed,
            at: DateTime.now(),
            isMine: true,
          ),
        ],
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(sendError: () => '$error');
    }
  }

  void setOpen(bool isOpen) => state = state.copyWith(
    isOpen: isOpen,
    unreadCount: isOpen ? 0 : state.unreadCount,
  );

  void _onEvent(CallEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case CallJoined():
        state = ChatState(isOpen: state.isOpen);
      case DataMessageReceived(:final fromUid):
        if (CallMessenger.read(event) case ChatMessageSent(:final text)) {
          state = state.copyWith(
            entries: [
              ...state.entries,
              ChatEntry(
                fromUid: fromUid,
                text: text,
                at: DateTime.now(),
                isMine: false,
              ),
            ],
            unreadCount: state.isOpen ? 0 : state.unreadCount + 1,
          );
        }
      default:
        break;
    }
  }
}
