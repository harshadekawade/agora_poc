import 'package:agora_poc/features/call/presentation/layout/call_layout_planner.dart';
import 'package:agora_poc/features/call/presentation/state/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

CallState callWith(
  List<int> uids, {
  Map<int, int> screens = const {},
  CallLayout layout = CallLayout.grid,
  int? pinned,
  int? speaker,
}) => CallState(
  status: CallStatus.inCall,
  participants: {for (final uid in uids) uid: Participant(uid: uid)},
  screenShareOwners: screens,
  layout: layout,
  pinnedUid: pinned,
  activeSpeakerUid: speaker,
);

void main() {
  group('tiles', () {
    test('screens first, then people, then us last', () {
      final tiles = CallLayoutPlanner.tiles(
        callWith([1, 9, 2], screens: {9: 1}),
      );
      expect(tiles, [
        const CallTile.remote(9),
        const CallTile.remote(1),
        const CallTile.remote(2),
        const CallTile.localCamera(),
      ]);
    });
  });

  group('main tile', () {
    test('pinned beats screen share beats active speaker', () {
      final base = {9: 1};
      expect(
        CallLayoutPlanner.mainTile(
          callWith([1, 2, 9], screens: base, pinned: 2, speaker: 1),
        ),
        const CallTile.remote(2),
      );
      expect(
        CallLayoutPlanner.mainTile(
          callWith([1, 2, 9], screens: base, speaker: 2),
        ),
        const CallTile.remote(9),
      );
      expect(
        CallLayoutPlanner.mainTile(callWith([1, 2], speaker: 2)),
        const CallTile.remote(2),
      );
    });

    test('falls back to the first person, then to us', () {
      expect(
        CallLayoutPlanner.mainTile(callWith([4, 5])),
        const CallTile.remote(4),
      );
      expect(
        CallLayoutPlanner.mainTile(callWith([])),
        const CallTile.localCamera(),
      );
    });

    test('a pin on someone who left is ignored', () {
      expect(
        CallLayoutPlanner.mainTile(callWith([4], pinned: 99)),
        const CallTile.remote(4),
      );
    });
  });

  test('grid shapes for 1–9 tiles', () {
    String shape(int n) {
      final s = CallLayoutPlanner.gridShape(n);
      return '${s.columns}x${s.rows}';
    }

    expect(
      [for (var n = 1; n <= 9; n++) shape(n)],
      ['1x1', '1x2', '2x2', '2x2', '2x3', '2x3', '3x3', '3x3', '3x3'],
    );
  });

  group('high-quality streams', () {
    test('1:1 grid: the other person gets full quality', () {
      expect(CallLayoutPlanner.highQualityUids(callWith([5])), {5});
    });

    test('crowded grid: only screen shares get full quality', () {
      expect(
        CallLayoutPlanner.highQualityUids(
          callWith([1, 2, 3, 9], screens: {9: 1}),
        ),
        {9},
      );
    });

    test('speaker view: the main tile and screens get full quality', () {
      expect(
        CallLayoutPlanner.highQualityUids(
          callWith([1, 2, 3], layout: CallLayout.speaker, speaker: 3),
        ),
        {3},
      );
    });
  });

  test('landscape flips the grid so tiles stay wide', () {
    String shape(int n) {
      final s = CallLayoutPlanner.gridShape(n, isWide: true);
      return '${s.columns}x${s.rows}';
    }

    expect([shape(2), shape(4), shape(6)], ['2x1', '2x2', '3x2']);
  });

  test('only alone or 1:1 in grid mode is full-bleed', () {
    expect(CallLayoutPlanner.isFullBleed(callWith([])), isTrue);
    expect(CallLayoutPlanner.isFullBleed(callWith([5])), isTrue);
    expect(CallLayoutPlanner.isFullBleed(callWith([5, 6])), isFalse);
    expect(
      CallLayoutPlanner.isFullBleed(callWith([5], layout: CallLayout.speaker)),
      isFalse,
    );
  });
}
