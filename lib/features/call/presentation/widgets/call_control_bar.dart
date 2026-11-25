import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strings/poc_strings.dart';
import '../providers/call_providers.dart';
import '../state/call_state.dart';

/// The five everyday controls plus Leave.
class CallControlBar extends ConsumerWidget {
  const CallControlBar({
    super.key,
    required this.state,
    required this.onOpenChat,
    required this.onOpenMore,
    required this.onLeave,
    this.isCompact = false,
  });

  /// Landscape: icons only and less padding, to save scarce height.
  static const _maxBarWidth = 640.0;

  final CallState state;
  final bool isCompact;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenMore;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(callControllerProvider.notifier);
    final unread = ref.watch(
      chatControllerProvider.select((s) => s.unreadCount),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxBarWidth),
            child: Padding(
              padding: isCompact
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
                  : const EdgeInsets.fromLTRB(8, 12, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final button in <Widget>[
                    CallControlButton(
                      isLabelVisible: !isCompact,
                      icon: state.isMicMuted ? Icons.mic_off : Icons.mic,
                      label: state.isMicMuted
                          ? PocStrings.unmute
                          : PocStrings.mute,
                      isOff: state.isMicMuted,
                      onPressed: controller.toggleMic,
                    ),
                    CallControlButton(
                      isLabelVisible: !isCompact,
                      icon: state.isCameraOn
                          ? Icons.videocam
                          : Icons.videocam_off,
                      label: state.isCameraOn
                          ? PocStrings.cameraOff
                          : PocStrings.cameraOn,
                      isOff: !state.isCameraOn,
                      onPressed: controller.toggleCamera,
                    ),
                    _AudioOutputButton(
                      output: state.audioOutput,
                      isLabelVisible: !isCompact,
                      onSelected: controller.setAudioOutput,
                    ),
                    CallControlButton(
                      isLabelVisible: !isCompact,
                      icon: Icons.chat_bubble_outline,
                      label: PocStrings.chat,
                      badgeCount: unread,
                      onPressed: onOpenChat,
                    ),
                    CallControlButton(
                      isLabelVisible: !isCompact,
                      icon: Icons.more_horiz,
                      label: PocStrings.more,
                      onPressed: onOpenMore,
                    ),
                    CallControlButton(
                      isLabelVisible: !isCompact,
                      icon: Icons.call_end,
                      label: PocStrings.leave,
                      isDestructive: true,
                      onPressed: onLeave,
                    ),
                  ])
                    // Equal shares, so labels ellipsize instead of overflowing.
                    Flexible(child: button),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Speaker, earpiece or sound off, picked from a small menu.
class _AudioOutputButton extends StatelessWidget {
  const _AudioOutputButton({
    required this.output,
    required this.isLabelVisible,
    required this.onSelected,
  });

  final CallAudioOutput output;
  final bool isLabelVisible;
  final ValueChanged<CallAudioOutput> onSelected;

  static IconData _icon(CallAudioOutput output) => switch (output) {
    CallAudioOutput.speaker => Icons.volume_up,
    CallAudioOutput.earpiece => Icons.phone_in_talk,
    CallAudioOutput.off => Icons.volume_off,
  };

  static String _label(CallAudioOutput output) => switch (output) {
    CallAudioOutput.speaker => PocStrings.speaker,
    CallAudioOutput.earpiece => PocStrings.earpiece,
    CallAudioOutput.off => PocStrings.soundOff,
  };

  static String _menuLabel(CallAudioOutput output) => switch (output) {
    CallAudioOutput.speaker => PocStrings.audioSpeakerOption,
    CallAudioOutput.earpiece => PocStrings.audioEarpieceOption,
    CallAudioOutput.off => PocStrings.audioOffOption,
  };

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final option in CallAudioOutput.values)
          MenuItemButton(
            leadingIcon: Icon(_icon(option)),
            trailingIcon: option == output ? const Icon(Icons.check) : null,
            onPressed: () => onSelected(option),
            child: Text(_menuLabel(option)),
          ),
      ],
      builder: (context, menu, _) => CallControlButton(
        isLabelVisible: isLabelVisible,
        icon: _icon(output),
        label: _label(output),
        isOff: output == CallAudioOutput.off,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

class CallControlButton extends StatelessWidget {
  const CallControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isOff = false,
    this.isDestructive = false,
    this.badgeCount = 0,
    this.isLabelVisible = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Muted / camera off: shown inverted so the state is obvious.
  final bool isOff;
  final bool isDestructive;
  final int badgeCount;
  final bool isLabelVisible;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = isDestructive
        ? (scheme.error, scheme.onError)
        : isOff
        ? (scheme.inverseSurface, scheme.onInverseSurface)
        : (scheme.surfaceContainerHighest, scheme.onSurface);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Badge(
          isLabelVisible: badgeCount > 0,
          label: Text('$badgeCount'),
          child: IconButton.filled(
            onPressed: onPressed,
            tooltip: label,
            icon: Icon(icon),
            style: IconButton.styleFrom(
              backgroundColor: background,
              foregroundColor: foreground,
              minimumSize: const Size.square(52),
            ),
          ),
        ),
        if (isLabelVisible) ...[
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ],
    );
  }
}
