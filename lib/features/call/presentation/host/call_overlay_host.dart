import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/app_navigator.dart';
import '../../../../core/strings/poc_strings.dart';
import '../layout/call_layout_planner.dart';
import '../providers/call_providers.dart';
import '../screens/call_screen.dart';
import '../state/call_labels.dart';
import '../state/call_state.dart';
import '../state/feature_states.dart';
import '../state/participant_names.dart';
import '../widgets/floating_call_window.dart';
import '../widgets/participant_tile.dart';

/// App-wide call plumbing, so it works whatever screen is showing:
/// system PiP (lifecycle + Android PiP layout), the in-app floating window,
/// the host's mute prompt and capture notices.
class CallOverlayHost extends ConsumerStatefulWidget {
  const CallOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CallOverlayHost> createState() => _CallOverlayHostState();
}

class _CallOverlayHostState extends ConsumerState<CallOverlayHost>
    with WidgetsBindingObserver {
  bool _isMutePromptOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(callControllerProvider.notifier).onAppLifecycleChanged(state);
  }

  void _expandCall() {
    ref.read(callControllerProvider.notifier).setMinimized(false);
    appNavigatorKey.currentState?.push(CallScreen.route());
  }

  void _onCallChanged(CallState? previous, CallState next) {
    final asker = next.pendingMuteRequestFromUid;
    if (asker != null && previous?.pendingMuteRequestFromUid != asker) {
      _showMutePrompt(next.nameOfUid(asker));
    }
    final wasMinimised = previous?.isMinimized ?? false;
    final failure = next.failure;
    if (wasMinimised && next.status == CallStatus.failed && failure != null) {
      _showMessage(failure.label);
    }
  }

  void _onCaptureChanged(CaptureState? previous, CaptureState next) {
    final message = next.message;
    if (message == null || message == previous?.message) return;
    _showMessage(message);
    ref.read(captureControllerProvider.notifier).clearMessage();
  }

  void _showMessage(String message) => appMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _showMutePrompt(String hostName) async {
    final context = appNavigatorKey.currentContext;
    if (context == null || _isMutePromptOpen) return;
    _isMutePromptOpen = true;
    final controller = ref.read(callControllerProvider.notifier);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.mic_off),
        title: const Text(PocStrings.muteRequestTitle),
        content: Text(hostName),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(PocStrings.muteRequestIgnore),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(PocStrings.muteRequestAccept),
          ),
        ],
      ),
    );
    _isMutePromptOpen = false;
    if (!mounted) return;
    if (accepted ?? false) {
      await controller.acceptMuteRequest();
    } else {
      controller.dismissMuteRequest();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(callControllerProvider, _onCallChanged);
    ref.listen(captureControllerProvider, _onCaptureChanged);
    final call = ref.watch(callControllerProvider);

    // Android shrinks the whole activity into the PiP window, so show only
    // the main video there. iOS draws its own PiP window natively.
    final isAndroidPip =
        call.isPipActive &&
        call.isLive &&
        defaultTargetPlatform == TargetPlatform.android;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Kept mounted (just hidden) during PiP: removing it threw away the
        // whole screen stack, so expanding PiP landed on Home, not the call.
        Offstage(offstage: isAndroidPip, child: widget.child),
        if (isAndroidPip)
          ParticipantTile(
            tile: CallLayoutPlanner.mainTile(call),
            state: call,
            isCompact: true,
          )
        else if (call.isLive && call.isMinimized)
          FloatingCallWindow(state: call, onExpand: _expandCall),
      ],
    );
  }
}
