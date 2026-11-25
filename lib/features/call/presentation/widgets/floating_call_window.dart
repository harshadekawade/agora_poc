import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../layout/call_layout_planner.dart';
import '../providers/call_providers.dart';
import '../state/call_state.dart';
import 'participant_tile.dart';

/// In-app PiP: a draggable mini call window shown over any screen while the
/// call is minimised. Tap to go back to the call.
///
/// It sits above the Navigator, so it must not use Tooltip (no Overlay).
class FloatingCallWindow extends ConsumerStatefulWidget {
  const FloatingCallWindow({
    super.key,
    required this.state,
    required this.onExpand,
  });

  final CallState state;
  final VoidCallback onExpand;

  @override
  ConsumerState<FloatingCallWindow> createState() => _FloatingCallWindowState();
}

class _FloatingCallWindowState extends ConsumerState<FloatingCallWindow> {
  static const _width = 116.0;
  static const _height = 164.0;
  static const _margin = 12.0;
  static const _endButtonSize = 32.0;

  /// Top-left corner; null until first laid out (then bottom-right).
  Offset? _position;

  Offset _clamp(Offset position, Size screen, EdgeInsets padding) => Offset(
    position.dx.clamp(_margin, screen.width - _width - _margin),
    position.dy.clamp(
      padding.top + _margin,
      screen.height - _height - padding.bottom - _margin,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final scheme = Theme.of(context).colorScheme;
    final position = _clamp(
      _position ??
          Offset(
            screen.width - _width - _margin,
            screen.height - _height - padding.bottom - 96,
          ),
      screen,
      padding,
    );
    final main = CallLayoutPlanner.mainTile(widget.state);

    return Positioned(
      left: position.dx,
      top: position.dy,
      width: _width,
      height: _height,
      child: GestureDetector(
        onTap: widget.onExpand,
        onPanUpdate: (details) => setState(
          () => _position = _clamp(position + details.delta, screen, padding),
        ),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ParticipantTile(tile: main, state: widget.state, isCompact: true),
              Positioned(
                top: 4,
                right: 4,
                width: _endButtonSize,
                height: _endButtonSize,
                child: Material(
                  color: scheme.error,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: ref.read(callControllerProvider.notifier).leave,
                    child: Icon(
                      Icons.call_end,
                      size: 18,
                      color: scheme.onError,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
