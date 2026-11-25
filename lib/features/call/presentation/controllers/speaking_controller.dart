import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/call_engine.dart';
import '../providers/call_providers.dart';

/// Volume per uid (0 = us), for the "who is talking" highlight.
class SpeakingController extends Notifier<Map<int, int>> {
  /// Agora volume is 0–255; above this counts as talking.
  static const speakingThreshold = 25;

  static const _localUid = 0;

  @override
  Map<int, int> build() {
    final events = ref.watch(callEngineProvider).events.listen(_onEvent);
    ref.onDispose(events.cancel);
    return const {};
  }

  bool isSpeaking(int uid) => (state[uid] ?? 0) > speakingThreshold;

  /// Agora sends two separate reports: one with only our own volume (uid 0),
  /// and one listing the loudest remote speakers. Anyone missing from the
  /// remote report is silent, so it replaces all remote entries.
  void _onEvent(CallEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case VolumesUpdated(:final volumes):
        final isLocalReport =
            volumes.length == 1 && volumes.containsKey(_localUid);
        state = isLocalReport
            ? {...state, ...volumes}
            : {
                if (state.containsKey(_localUid))
                  _localUid: state[_localUid] ?? 0,
                ...volumes,
              };
      case CallLeft():
        state = const {};
      default:
        break;
    }
  }
}
