import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strings/poc_strings.dart';
import '../../domain/call_engine.dart';
import '../controllers/speaking_controller.dart';
import '../layout/call_layout_planner.dart';
import '../providers/call_providers.dart';
import '../state/call_state.dart';
import '../state/participant_names.dart';
import 'participant_avatar.dart';
import 'video_view_keys.dart';

/// One person's (or screen's) video with name, mic, hand and speaking ring.
class ParticipantTile extends ConsumerWidget {
  const ParticipantTile({
    super.key,
    required this.tile,
    required this.state,
    this.isCompact = false,
    this.labelBottomInset = _defaultLabelInset,
    this.isZoomable = false,
    this.onTap,
  });

  static const _defaultLabelInset = 8.0;

  static const _radius = 16.0;
  static const _compactRadius = 12.0;

  final CallTile tile;
  final CallState state;

  /// Thumbnails: smaller avatar and label.
  final bool isCompact;

  /// Full-screen tiles lift the name label above the control bar.
  final double labelBottomInset;

  /// Pinch-to-zoom for a shared screen shown as the main tile.
  final bool isZoomable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final radius = isCompact ? _compactRadius : _radius;
    // Shared screens are letterboxed, so their bars should read as black.
    final isScreen = !tile.isLocal && state.isScreenShare(tile.uid);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: isScreen ? scheme.scrim : scheme.surfaceContainerHigh,
            ),
            _TileVideo(
              tile: tile,
              state: state,
              isCompact: isCompact,
              isZoomable: isZoomable && isScreen,
            ),
            _SpeakingRing(tile: tile, radius: radius),
            // Stats sit just above the name, never at the top where the
            // call's top bar covers them in full-screen view.
            Positioned(
              left: 8,
              right: 8,
              bottom: labelBottomInset,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isCompact) _TileStatsBadge(tile: tile),
                  _TileLabel(tile: tile, state: state, isCompact: isCompact),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileVideo extends ConsumerWidget {
  const _TileVideo({
    required this.tile,
    required this.state,
    required this.isCompact,
    required this.isZoomable,
  });

  static const _maxZoom = 4.0;

  final CallTile tile;
  final CallState state;
  final bool isCompact;
  final bool isZoomable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views = ref.watch(callVideoViewFactoryProvider);
    final isAudioOnly = ref.watch(
      mediaSettingsControllerProvider.select((s) => s.isAudioOnly),
    );
    final avatar = Center(
      child: ParticipantAvatar(
        name: state.nameOfTile(tile),
        seed: tile.uid,
        radius: isCompact ? 22 : 40,
      ),
    );

    // Moves the native view with the tile when the layout changes.
    final videoKey = VideoViewKeys.of(context, tile);

    switch (tile.kind) {
      case CallTileKind.localCamera:
        if (!state.isCameraOn) return avatar;
        return KeyedSubtree(key: videoKey, child: views.localCamera());
      case CallTileKind.remote:
        final participant = state.participants[tile.uid];
        final status = participant?.videoStatus ?? RemoteVideoStatus.connecting;
        if (isAudioOnly || status == RemoteVideoStatus.off) return avatar;
        final isScreen = state.isScreenShare(tile.uid);
        final video = KeyedSubtree(
          key: videoKey,
          child: views.remote(tile.uid, fitWholeFrame: isScreen),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            // The video view stays mounted while connecting, so the first
            // frame can draw the moment it arrives.
            if (isZoomable)
              InteractiveViewer(maxScale: _maxZoom, child: video)
            else
              video,
            if (status == RemoteVideoStatus.connecting)
              _ConnectingOverlay(avatar: avatar, isCompact: isCompact),
            if (participant?.isFrozenNoticeVisible ?? false)
              Center(child: _FrozenChip(isCompact: isCompact)),
          ],
        );
    }
  }
}

/// Initials with a spinner until the first frame arrives, instead of an
/// empty grey box.
class _ConnectingOverlay extends StatelessWidget {
  const _ConnectingOverlay({required this.avatar, required this.isCompact});

  /// Spinner ring sits just outside the avatar, so it adds no height and
  /// never collides with the name label on small thumbnails.
  static const _ringGap = 8.0;
  static const _compactAvatarDiameter = 44.0;
  static const _avatarDiameter = 80.0;

  final Widget avatar;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ringSize =
        (isCompact ? _compactAvatarDiameter : _avatarDiameter) + _ringGap;
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: ringSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const CircularProgressIndicator(strokeWidth: 2),
                avatar,
              ],
            ),
          ),
          if (!isCompact) ...[
            const SizedBox(height: 12),
            Text(
              PocStrings.connectingVideo,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _FrozenChip extends StatelessWidget {
  const _FrozenChip({required this.isCompact});

  /// Thumbnails are too narrow for the text, so they show only the icon.
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isCompact) {
      // Semantics, not Tooltip: compact tiles also appear in the floating
      // call window, which sits above the Navigator and has no Overlay.
      return Semantics(
        label: PocStrings.videoFrozen,
        child: CircleAvatar(
          radius: 14,
          backgroundColor: scheme.errorContainer,
          child: Icon(Icons.ac_unit, size: 16, color: scheme.onErrorContainer),
        ),
      );
    }
    return Chip(
      avatar: Icon(Icons.ac_unit, size: 16, color: scheme.onErrorContainer),
      label: const Text(PocStrings.videoFrozen),
      backgroundColor: scheme.errorContainer,
      labelStyle: TextStyle(color: scheme.onErrorContainer),
    );
  }
}

/// Rebuilds ~3×/s with volume, so it watches only its own uid's level.
class _SpeakingRing extends ConsumerWidget {
  const _SpeakingRing({required this.tile, required this.radius});

  static const _ringWidth = 3.0;

  final CallTile tile;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSpeaking = ref.watch(
      speakingControllerProvider.select(
        (volumes) =>
            (volumes[tile.uid] ?? 0) > SpeakingController.speakingThreshold,
      ),
    );
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: isSpeaking
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: _ringWidth,
          ),
        ),
      ),
    );
  }
}

class _TileLabel extends StatelessWidget {
  const _TileLabel({
    required this.tile,
    required this.state,
    required this.isCompact,
  });

  final CallTile tile;
  final CallState state;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final participant = state.participants[tile.uid];
    final isMicOff = switch (tile.kind) {
      CallTileKind.localCamera => state.isMicMuted,
      CallTileKind.remote =>
        !state.isScreenShare(tile.uid) && participant?.isMicOn == false,
    };
    final isHandRaised = switch (tile.kind) {
      CallTileKind.localCamera => state.isHandRaised,
      CallTileKind.remote => participant?.isHandRaised ?? false,
    };
    final isPinned = !tile.isLocal && state.pinnedUid == tile.uid;
    final textStyle =
        (isCompact
                ? Theme.of(context).textTheme.labelSmall
                : Theme.of(context).textTheme.labelMedium)
            ?.copyWith(color: scheme.onSurface);

    return Row(
      children: [
        Flexible(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isHandRaised) ...[
                    const Text('✋'),
                    const SizedBox(width: 4),
                  ],
                  if (isPinned) ...[
                    Icon(Icons.push_pin, size: 14, color: scheme.primary),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      state.labelOfTile(tile),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle,
                    ),
                  ),
                  if (isMicOff) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.mic_off, size: 14, color: scheme.error),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Resolution / fps / bitrate / loss, shown when the stats overlay is on.
class _TileStatsBadge extends ConsumerWidget {
  const _TileStatsBadge({required this.tile});

  static const _statsGap = 4.0;

  final CallTile tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsControllerProvider);
    if (!stats.isOverlayVisible) return const SizedBox.shrink();

    final String text;
    switch (tile.kind) {
      case CallTileKind.localCamera:
        final local = stats.localVideo;
        if (local == null) return const SizedBox.shrink();
        text =
            '↑ ${local.width}×${local.height} ${local.frameRate}fps '
            '${local.bitrateKbps}kbps';
      case CallTileKind.remote:
        final video = stats.remoteVideo[tile.uid];
        final audio = stats.remoteAudio[tile.uid];
        if (video == null) return const SizedBox.shrink();
        text =
            '${video.width}×${video.height} ${video.frameRate}fps '
            '${video.bitrateKbps}kbps ${video.isLowStream ? 'LOW' : 'HIGH'}\n'
            'loss v${video.packetLossPercent}% '
            'a${audio?.lossPercent ?? 0}% · delay ${video.delayMs}ms';
    }

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: _statsGap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
