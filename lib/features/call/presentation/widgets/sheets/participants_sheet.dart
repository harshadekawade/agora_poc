import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/strings/poc_strings.dart';
import '../../../domain/call_engine.dart';
import '../../../domain/call_session.dart';
import '../../providers/call_providers.dart';
import '../../state/call_labels.dart';
import '../../state/call_state.dart';
import '../../state/participant_names.dart';
import '../participant_avatar.dart';

class ParticipantsSheet extends ConsumerWidget {
  const ParticipantsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(callControllerProvider);
    final session = state.session;
    final people = state.people.toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '${PocStrings.participants} (${people.length + 1})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (session != null)
            _ParticipantRow(
              name: '${session.displayName} (${PocStrings.you})',
              uid: session.localUid,
              role: session.role,
              isMicOn: !state.isMicMuted,
              isCameraOn: state.isCameraOn,
              isHandRaised: state.isHandRaised,
            ),
          for (final person in people)
            _ParticipantRow(
              name: state.nameOfUid(person.uid),
              uid: person.uid,
              role: person.role,
              isMicOn: person.isMicOn,
              isCameraOn: person.videoStatus != RemoteVideoStatus.off,
              isHandRaised: person.isHandRaised,
              actions: _PersonActions(uid: person.uid, state: state),
            ),
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.name,
    required this.uid,
    required this.role,
    required this.isMicOn,
    required this.isCameraOn,
    required this.isHandRaised,
    this.actions,
  });

  final String name;
  final int uid;
  final ParticipantRole role;
  final bool isMicOn;
  final bool isCameraOn;
  final bool isHandRaised;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: ParticipantAvatar(name: name, seed: uid, radius: 20),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${role.label} · uid $uid'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isHandRaised) const Text('✋ '),
          Icon(
            isMicOn ? Icons.mic : Icons.mic_off,
            size: 20,
            color: isMicOn ? scheme.onSurfaceVariant : scheme.error,
          ),
          const SizedBox(width: 4),
          Icon(
            isCameraOn ? Icons.videocam : Icons.videocam_off,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          ?actions,
        ],
      ),
    );
  }
}

enum _PersonAction { pin, snapshot, record, askToMute, remove }

class _PersonActions extends ConsumerWidget {
  const _PersonActions({required this.uid, required this.state});

  final int uid;
  final CallState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.read(callControllerProvider.notifier);
    final capture = ref.read(captureControllerProvider.notifier);
    final channelId = state.session?.channelId;

    return PopupMenuButton<_PersonAction>(
      onSelected: (action) {
        Navigator.of(context).pop();
        switch (action) {
          case _PersonAction.pin:
            call.togglePin(uid);
          case _PersonAction.snapshot:
            capture.takeSnapshot(uid);
          case _PersonAction.record:
            if (channelId != null) {
              capture.toggleRecording(channelId: channelId, uid: uid);
            }
          case _PersonAction.askToMute:
            call.requestMute(uid);
          case _PersonAction.remove:
            call.requestRemove(uid);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _PersonAction.pin,
          child: Text(
            state.pinnedUid == uid ? PocStrings.unpin : PocStrings.pin,
          ),
        ),
        const PopupMenuItem(
          value: _PersonAction.snapshot,
          child: Text(PocStrings.snapshot),
        ),
        const PopupMenuItem(
          value: _PersonAction.record,
          child: Text(PocStrings.recordThisPerson),
        ),
        if (state.isHost) ...[
          const PopupMenuItem(
            value: _PersonAction.askToMute,
            child: Text(PocStrings.askToMute),
          ),
          const PopupMenuItem(
            value: _PersonAction.remove,
            child: Text(PocStrings.removeFromCall),
          ),
        ],
      ],
    );
  }
}
