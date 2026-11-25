import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strings/poc_strings.dart';
import '../layout/call_layout_planner.dart';
import '../providers/call_providers.dart';
import '../state/call_state.dart';
import 'participant_tile.dart';

/// Picks the layout: alone, 1:1 (FaceTime-style), grid, or speaker view,
/// each in a portrait and a landscape (wide) form.
///
/// Alone and 1:1 are full-bleed (drawn behind the bars), so they lift labels
/// by [overlayBottomInset]. Grid and speaker get only the space between the
/// bars (see CallScreen), so nothing overlaps.
class CallVideoArea extends ConsumerWidget {
  const CallVideoArea({
    super.key,
    required this.state,
    this.overlayBottomInset = 0,
  });

  final CallState state;
  final double overlayBottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(callControllerProvider.notifier);
    final isWide = MediaQuery.orientationOf(context) == Orientation.landscape;
    final tiles = CallLayoutPlanner.tiles(state);
    void pin(CallTile tile) {
      if (!tile.isLocal) controller.togglePin(tile.uid);
    }

    if (state.layout == CallLayout.speaker && tiles.length > 1) {
      return _SpeakerView(
        state: state,
        tiles: tiles,
        isWide: isWide,
        onTileTap: pin,
      );
    }
    return switch (tiles.length) {
      1 => _AloneView(
        state: state,
        tile: tiles.single,
        labelInset: overlayBottomInset,
      ),
      2 => _OneToOneView(
        state: state,
        tiles: tiles,
        isWide: isWide,
        bottomInset: overlayBottomInset,
      ),
      _ => _GridView(
        state: state,
        tiles: tiles,
        isWide: isWide,
        onTileTap: pin,
      ),
    };
  }
}

class _AloneView extends StatelessWidget {
  const _AloneView({
    required this.state,
    required this.tile,
    required this.labelInset,
  });

  /// Below the centred avatar (shown when the camera is off), not on it.
  static const _hintAlignment = Alignment(0, 0.35);

  final CallState state;
  final CallTile tile;
  final double labelInset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ParticipantTile(tile: tile, state: state, labelBottomInset: labelInset),
        Align(
          alignment: _hintAlignment,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                PocStrings.waitingForOthers,
                style: TextStyle(color: scheme.onSurface),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Other person full screen, us in a small tile bottom-right above the
/// controls (clear of the top bar and banners).
class _OneToOneView extends StatelessWidget {
  const _OneToOneView({
    required this.state,
    required this.tiles,
    required this.isWide,
    required this.bottomInset,
  });

  static const _portraitWidthFactor = 0.3;
  static const _wideWidthFactor = 0.18;
  static const _portraitAspectRatio = 3 / 4;
  static const _wideAspectRatio = 4 / 3;
  static const _margin = 12.0;

  final CallState state;
  final List<CallTile> tiles;
  final bool isWide;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final remote = tiles.firstWhere((t) => !t.isLocal, orElse: () => tiles[0]);
    final local = tiles.firstWhere((t) => t != remote);
    return Stack(
      fit: StackFit.expand,
      children: [
        ParticipantTile(
          tile: remote,
          state: state,
          labelBottomInset: bottomInset,
          isZoomable: true,
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.only(right: _margin, bottom: bottomInset),
            child: FractionallySizedBox(
              widthFactor: isWide ? _wideWidthFactor : _portraitWidthFactor,
              child: AspectRatio(
                aspectRatio: isWide ? _wideAspectRatio : _portraitAspectRatio,
                child: ParticipantTile(
                  tile: local,
                  state: state,
                  isCompact: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GridView extends StatelessWidget {
  const _GridView({
    required this.state,
    required this.tiles,
    required this.isWide,
    required this.onTileTap,
  });

  static const _gap = 6.0;
  static const _compactAbove = 4;

  final CallState state;
  final List<CallTile> tiles;
  final bool isWide;
  final ValueChanged<CallTile> onTileTap;

  @override
  Widget build(BuildContext context) {
    final visible = tiles.take(CallLayoutPlanner.maxGridTiles).toList();
    final shape = CallLayoutPlanner.gridShape(visible.length, isWide: isWide);
    final rows = <List<CallTile>>[
      for (var start = 0; start < visible.length; start += shape.columns)
        visible.skip(start).take(shape.columns).toList(),
    ];

    return Padding(
      padding: const EdgeInsets.all(_gap / 2),
      child: Column(
        children: [
          for (final row in rows)
            Expanded(
              child: Row(
                children: [
                  for (final tile in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(_gap / 2),
                        child: ParticipantTile(
                          tile: tile,
                          state: state,
                          isCompact: visible.length > _compactAbove,
                          onTap: () => onTileTap(tile),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One big tile plus everyone else in a strip: below it in portrait, in a
/// column on the right in landscape.
class _SpeakerView extends StatelessWidget {
  const _SpeakerView({
    required this.state,
    required this.tiles,
    required this.isWide,
    required this.onTileTap,
  });

  static const _stripExtent = 120.0;
  static const _wideStripExtent = 168.0;
  static const _thumbnailAspectRatio = 3 / 4;
  static const _wideThumbnailAspectRatio = 4 / 3;
  static const _gap = 8.0;

  final CallState state;
  final List<CallTile> tiles;
  final bool isWide;
  final ValueChanged<CallTile> onTileTap;

  @override
  Widget build(BuildContext context) {
    final main = CallLayoutPlanner.mainTile(state);
    final others = tiles.where((t) => t != main).toList();

    final mainTile = Padding(
      padding: const EdgeInsets.all(_gap / 2),
      child: ParticipantTile(
        tile: main,
        state: state,
        isZoomable: true,
        onTap: () => onTileTap(main),
      ),
    );
    final strip = ListView.separated(
      scrollDirection: isWide ? Axis.vertical : Axis.horizontal,
      padding: const EdgeInsets.all(_gap / 2),
      itemCount: others.length,
      separatorBuilder: (_, _) => const SizedBox.square(dimension: _gap),
      itemBuilder: (context, index) => AspectRatio(
        aspectRatio: isWide ? _wideThumbnailAspectRatio : _thumbnailAspectRatio,
        child: ParticipantTile(
          tile: others[index],
          state: state,
          isCompact: true,
          onTap: () => onTileTap(others[index]),
        ),
      ),
    );

    return isWide
        ? Row(
            children: [
              Expanded(child: mainTile),
              SizedBox(width: _wideStripExtent, child: strip),
            ],
          )
        : Column(
            children: [
              Expanded(child: mainTile),
              SizedBox(height: _stripExtent, child: strip),
            ],
          );
  }
}
