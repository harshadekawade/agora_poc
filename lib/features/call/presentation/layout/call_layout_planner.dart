import 'package:flutter/foundation.dart';

import '../state/call_state.dart';

enum CallTileKind { localCamera, remote }

/// One video slot on screen.
@immutable
class CallTile {
  const CallTile.localCamera() : kind = CallTileKind.localCamera, uid = 0;
  const CallTile.remote(this.uid) : kind = CallTileKind.remote;

  final CallTileKind kind;

  /// Remote uid; 0 for our own tiles.
  final int uid;

  bool get isLocal => kind != CallTileKind.remote;

  @override
  bool operator ==(Object other) =>
      other is CallTile && other.kind == kind && other.uid == uid;

  @override
  int get hashCode => Object.hash(kind, uid);
}

@immutable
class GridShape {
  const GridShape({required this.columns, required this.rows});
  final int columns;
  final int rows;
}

/// Pure layout rules, kept out of widgets so they can be unit tested.
abstract final class CallLayoutPlanner {
  /// More tiles than this would be unreadably small on a phone.
  static const maxGridTiles = 9;

  /// Up to this many tiles, everyone is big enough to need full quality.
  static const _fullQualityTileLimit = 2;

  /// Screen shares first (they carry the content), then people in join
  /// order, then us last. Our own shared screen is not shown back to us
  /// (it would be a black self-capture); the sharing banner covers it.
  static List<CallTile> tiles(CallState state) => [
    for (final uid in state.participants.keys)
      if (state.isScreenShare(uid)) CallTile.remote(uid),
    for (final uid in state.participants.keys)
      if (!state.isScreenShare(uid)) CallTile.remote(uid),
    const CallTile.localCamera(),
  ];

  /// Who fills the screen in speaker view: pinned, else someone's screen,
  /// else whoever is talking, else the first other person, else us.
  static CallTile mainTile(CallState state) {
    final pinned = state.pinnedUid;
    if (pinned != null && state.participants.containsKey(pinned)) {
      return CallTile.remote(pinned);
    }
    for (final uid in state.participants.keys) {
      if (state.isScreenShare(uid)) return CallTile.remote(uid);
    }
    final speaker = state.activeSpeakerUid;
    if (speaker != null && state.participants.containsKey(speaker)) {
      return CallTile.remote(speaker);
    }
    final firstPerson = state.people.firstOrNull;
    if (firstPerson != null) return CallTile.remote(firstPerson.uid);
    return const CallTile.localCamera();
  }

  /// Portrait stacks tiles in rows; [isWide] (landscape) flips the shape
  /// so tiles stay close to the video's own proportions.
  static GridShape gridShape(int tileCount, {bool isWide = false}) {
    final portrait = switch (tileCount) {
      <= 1 => const GridShape(columns: 1, rows: 1),
      2 => const GridShape(columns: 1, rows: 2),
      <= 4 => const GridShape(columns: 2, rows: 2),
      <= 6 => const GridShape(columns: 2, rows: 3),
      _ => const GridShape(columns: 3, rows: 3),
    };
    return isWide
        ? GridShape(columns: portrait.rows, rows: portrait.columns)
        : portrait;
  }

  /// Alone or 1:1 in grid mode: video fills the screen behind the bars.
  /// Everything else is laid out between the bars so nothing overlaps.
  static bool isFullBleed(CallState state) =>
      state.layout == CallLayout.grid && tiles(state).length <= 2;

  /// Remote uids that should get the full-quality stream; everyone else
  /// gets Agora's low stream, which saves bandwidth (and cost) for small
  /// tiles. Screen shares always get full quality so text stays readable.
  static Set<int> highQualityUids(CallState state) {
    final remoteUids = state.participants.keys;
    final screens = remoteUids.where(state.isScreenShare);
    switch (state.layout) {
      case CallLayout.speaker:
        final main = mainTile(state);
        return {...screens, if (!main.isLocal) main.uid};
      case CallLayout.grid:
        final visible = tiles(state).take(maxGridTiles).length;
        if (visible <= _fullQualityTileLimit) return remoteUids.toSet();
        return screens.toSet();
    }
  }
}
