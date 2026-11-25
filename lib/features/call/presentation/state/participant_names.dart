import '../../../../core/strings/poc_strings.dart';
import '../layout/call_layout_planner.dart';
import 'call_state.dart';

extension CallStateNames on CallState {
  /// Last 4 digits keep fallback names short but distinct.
  static const _shortUidModulo = 10000;

  String nameOfUid(int uid) {
    final owner = screenShareOwners[uid];
    if (owner != null) return '${nameOfUid(owner)} · ${PocStrings.screenOf}';
    return participants[uid]?.name ?? 'Guest ${uid % _shortUidModulo}';
  }

  /// The person's name, used for avatar initials.
  String nameOfTile(CallTile tile) => switch (tile.kind) {
    CallTileKind.localCamera => session?.displayName ?? PocStrings.you,
    CallTileKind.remote => nameOfUid(tile.uid),
  };

  /// The name tag on a tile. Our own tile just says "You": it is often a
  /// small thumbnail, and "Guest 4808 (You)" got cut off and was easy to
  /// confuse with the other person's auto-generated "Guest" name.
  String labelOfTile(CallTile tile) =>
      tile.isLocal ? PocStrings.you : nameOfTile(tile);
}
