import 'package:agora_poc/core/strings/poc_strings.dart';
import 'package:agora_poc/features/call/presentation/layout/call_layout_planner.dart';
import 'package:agora_poc/features/call/presentation/state/call_state.dart';
import 'package:agora_poc/features/call/presentation/state/participant_names.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/call_fakes.dart';

void main() {
  final state = CallState(
    session: testSession(),
    participants: const {5: Participant(uid: 5, name: 'Dr Rao')},
  );

  test('our own tile is tagged just "You"', () {
    expect(state.labelOfTile(const CallTile.localCamera()), PocStrings.you);
  });

  test('our initials still come from our name', () {
    expect(state.nameOfTile(const CallTile.localCamera()), 'Me');
  });

  test('other people are tagged with their name', () {
    expect(state.labelOfTile(const CallTile.remote(5)), 'Dr Rao');
  });
}
