import 'package:flutter/widgets.dart';

import '../layout/call_layout_planner.dart';

/// Keeps each tile's native video view alive when the layout changes.
///
/// When someone joins or leaves, the call switches between alone, 1:1, grid
/// and speaker layouts, which have different widget trees. Without a stable
/// key Flutter throws each video view away and creates a new one, which
/// shows grey or a stale frame until the next video frame arrives. A
/// [GlobalKey] per tile lets Flutter move the existing view instead.
///
/// Only the call screen provides a scope. The floating window, Android PiP
/// and pre-call preview have none, so the same key is never used twice.
class VideoViewKeys extends StatefulWidget {
  const VideoViewKeys({super.key, required this.child});

  final Widget child;

  /// The key for [tile]'s video view, or null outside the call screen.
  static GlobalKey? of(BuildContext context, CallTile tile) => context
      .dependOnInheritedWidgetOfExactType<_VideoViewKeysScope>()
      ?.keys
      .keyFor(tile);

  @override
  State<VideoViewKeys> createState() => _VideoViewKeysState();
}

class _VideoViewKeysState extends State<VideoViewKeys> {
  final _keys = _TileKeys();

  @override
  Widget build(BuildContext context) =>
      _VideoViewKeysScope(keys: _keys, child: widget.child);
}

class _TileKeys {
  final Map<CallTile, GlobalKey> _byTile = {};

  GlobalKey keyFor(CallTile tile) =>
      _byTile.putIfAbsent(tile, () => GlobalKey(debugLabel: 'video $tile'));
}

class _VideoViewKeysScope extends InheritedWidget {
  const _VideoViewKeysScope({required this.keys, required super.child});

  final _TileKeys keys;

  @override
  bool updateShouldNotify(_VideoViewKeysScope oldWidget) =>
      keys != oldWidget.keys;
}
