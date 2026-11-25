import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/strings/poc_strings.dart';
import '../../../domain/call_message.dart';
import '../../controllers/chat_controller.dart';
import '../../providers/call_providers.dart';
import '../../state/call_labels.dart';
import '../../state/feature_states.dart';
import '../../state/participant_names.dart';

class ChatSheet extends ConsumerStatefulWidget {
  const ChatSheet({super.key});

  @override
  ConsumerState<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends ConsumerState<ChatSheet> {
  final _input = TextEditingController();
  late final ChatController _chat;

  @override
  void initState() {
    super.initState();
    _chat = ref.read(chatControllerProvider.notifier);
    // Deferred: providers must not change while the sheet is building.
    Future.microtask(() => _chat.setOpen(true));
  }

  @override
  void dispose() {
    _input.dispose();
    Future.microtask(() => _chat.setOpen(false));
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await _chat.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final call = ref.watch(callControllerProvider);
    final sendError = chat.sendError;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Expanded(
              child: chat.entries.isEmpty
                  ? const Center(child: Text(PocStrings.chatEmpty))
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: chat.entries.length,
                      itemBuilder: (context, index) {
                        final entry =
                            chat.entries[chat.entries.length - 1 - index];
                        return _ChatBubble(
                          entry: entry,
                          senderName: entry.isMine
                              ? PocStrings.you
                              : call.nameOfUid(entry.fromUid),
                        );
                      },
                    ),
            ),
            if (sendError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  sendError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: CallMessageCodec.maxChatLength,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: PocStrings.chatHint,
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: PocStrings.send,
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.entry, required this.senderName});

  static const _maxWidthFraction = 0.75;

  final ChatEntry entry;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (background, foreground) = entry.isMine
        ? (scheme.primaryContainer, scheme.onPrimaryContainer)
        : (scheme.surfaceContainerHighest, scheme.onSurface);

    return Align(
      alignment: entry.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * _maxWidthFraction,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$senderName · ${hourMinuteLabel(entry.at)}',
                style: textTheme.labelSmall?.copyWith(color: foreground),
              ),
              const SizedBox(height: 2),
              Text(
                entry.text,
                style: textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
