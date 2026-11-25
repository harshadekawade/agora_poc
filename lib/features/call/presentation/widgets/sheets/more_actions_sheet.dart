import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/strings/poc_strings.dart';
import '../../layout/call_layout_planner.dart';
import '../../providers/call_providers.dart';
import '../../state/call_state.dart';
import 'call_sheets.dart';

/// Everything that doesn't fit on the control bar.
class MoreActionsSheet extends ConsumerWidget {
  const MoreActionsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(callControllerProvider);
    final settings = ref.watch(mediaSettingsControllerProvider);
    final isRecording = ref.watch(
      captureControllerProvider.select((s) => s.isRecording),
    );
    final isStatsOn = ref.watch(
      statsControllerProvider.select((s) => s.isOverlayVisible),
    );
    final call = ref.read(callControllerProvider.notifier);
    final media = ref.read(mediaSettingsControllerProvider.notifier);
    final capture = ref.read(captureControllerProvider.notifier);
    final canShareScreen = ref
        .watch(callCaptureProvider)
        .isScreenShareSupported;
    final main = CallLayoutPlanner.mainTile(state);
    final session = state.session;

    void run(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    final actions = [
      _Action(
        Icons.cameraswitch,
        PocStrings.switchCamera,
        () => run(call.switchCamera),
      ),
      _Action(
        Icons.screen_share,
        PocStrings.shareScreen,
        canShareScreen ? () => run(call.toggleScreenShare) : null,
        isActive: state.isScreenSharing,
        note: canShareScreen ? null : PocStrings.shareScreenUnsupported,
      ),
      _Action(
        Icons.back_hand_outlined,
        state.isHandRaised ? PocStrings.lowerHand : PocStrings.raiseHand,
        () => run(call.toggleHand),
        isActive: state.isHandRaised,
      ),
      _Action(
        state.layout == CallLayout.grid ? Icons.view_agenda : Icons.grid_view,
        state.layout == CallLayout.grid
            ? PocStrings.speakerView
            : PocStrings.gridView,
        () => run(
          () => call.setLayout(
            state.layout == CallLayout.grid
                ? CallLayout.speaker
                : CallLayout.grid,
          ),
        ),
      ),
      _Action(
        Icons.people_alt_outlined,
        PocStrings.participants,
        () => run(() => showParticipantsSheet(context)),
      ),
      _Action(
        Icons.photo_camera_outlined,
        PocStrings.snapshot,
        () => run(() => capture.takeSnapshot(main.isLocal ? 0 : main.uid)),
      ),
      _Action(
        Icons.fiber_manual_record_outlined,
        isRecording ? PocStrings.stopRecording : PocStrings.record,
        session == null
            ? null
            : () => run(
                () => capture.toggleRecording(
                  channelId: session.channelId,
                  uid: main.isLocal ? 0 : main.uid,
                ),
              ),
        isActive: isRecording,
      ),
      _Action(
        Icons.query_stats,
        PocStrings.stats,
        () => run(ref.read(statsControllerProvider.notifier).toggleOverlay),
        isActive: isStatsOn,
      ),
      _Action(
        Icons.receipt_long_outlined,
        PocStrings.eventLog,
        () => run(() => showEventLogSheet(context)),
      ),
      _Action(
        Icons.high_quality_outlined,
        PocStrings.quality,
        () => run(() => showQualitySheet(context)),
      ),
      _Action(
        Icons.graphic_eq,
        PocStrings.noiseSuppression,
        () => run(media.toggleNoiseSuppression),
        isActive: settings.isNoiseSuppressionOn,
      ),
      _Action(
        Icons.blur_on,
        PocStrings.blur,
        settings.isBlurSupported == false ? null : () => run(media.toggleBlur),
        isActive: settings.isBlurOn,
        note: settings.isBlurSupported == false
            ? PocStrings.blurUnsupported
            : null,
      ),
      _Action(
        Icons.face_retouching_natural,
        PocStrings.beauty,
        () => run(media.toggleBeauty),
        isActive: settings.isBeautyOn,
      ),
      _Action(
        Icons.headset_mic_outlined,
        PocStrings.audioOnly,
        () => run(media.toggleAudioOnly),
        isActive: settings.isAudioOnly,
      ),
      if (state.isHost)
        _Action(
          Icons.voice_over_off,
          PocStrings.muteEveryone,
          () => run(call.requestMuteEveryone),
        ),
    ];

    // Scrolls on short screens instead of overflowing.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                const minTileWidth = 84.0;
                final columns = (constraints.maxWidth / minTileWidth)
                    .floor()
                    .clamp(3, 6);
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.05,
                  children: [for (final action in actions) _ActionTile(action)],
                );
              },
            ),
            if (state.isHost) ...[
              const SizedBox(height: 12),
              Text(
                PocStrings.hostOnlyNote,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Action {
  const _Action(
    this.icon,
    this.label,
    this.onTap, {
    this.isActive = false,
    this.note,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;
  final String? note;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(this.action);

  final _Action action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEnabled = action.onTap != null;
    final (background, foreground) = action.isActive
        ? (scheme.primaryContainer, scheme.onPrimaryContainer)
        : (scheme.surfaceContainerHighest, scheme.onSurface);

    final tile = Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: action.onTap,
        child: Opacity(
          opacity: isEnabled ? 1 : 0.4,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, color: foreground),
                const SizedBox(height: 6),
                Text(
                  action.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final note = action.note;
    return note == null ? tile : Tooltip(message: note, child: tile);
  }
}
