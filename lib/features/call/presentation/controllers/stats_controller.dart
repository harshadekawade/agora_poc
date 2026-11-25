import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/call_engine.dart';
import '../providers/call_providers.dart';
import '../state/feature_states.dart';

/// Live numbers for the stats overlay, updated about every 2 seconds.
class StatsController extends Notifier<StatsState> {
  @override
  StatsState build() {
    final events = ref.watch(callEngineProvider).events.listen(_onEvent);
    ref.onDispose(events.cancel);
    return const StatsState();
  }

  void toggleOverlay() =>
      state = state.copyWith(isOverlayVisible: !state.isOverlayVisible);

  void _onEvent(CallEvent event) {
    if (!ref.mounted) return;
    switch (event) {
      case CallJoined():
        state = StatsState(isOverlayVisible: state.isOverlayVisible);
      case CallStatsUpdated(:final stats):
        state = state.copyWith(call: stats);
      case LocalVideoStatsUpdated(:final metrics):
        state = state.copyWith(localVideo: metrics);
      case RemoteVideoStatsUpdated(:final metrics):
        state = state.copyWith(
          remoteVideo: {...state.remoteVideo, metrics.uid: metrics},
        );
      case RemoteAudioStatsUpdated(:final metrics):
        state = state.copyWith(
          remoteAudio: {...state.remoteAudio, metrics.uid: metrics},
        );
      case RemoteUserLeft(:final uid):
        state = state.copyWith(
          remoteVideo: Map.of(state.remoteVideo)..remove(uid),
          remoteAudio: Map.of(state.remoteAudio)..remove(uid),
        );
      default:
        break;
    }
  }
}
