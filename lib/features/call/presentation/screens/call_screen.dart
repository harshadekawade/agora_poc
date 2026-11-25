import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strings/poc_strings.dart';
import '../layout/call_layout_planner.dart';
import '../providers/call_providers.dart';
import '../state/call_labels.dart';
import '../state/call_state.dart';
import '../widgets/call_banners.dart';
import '../widgets/call_control_bar.dart';
import '../widgets/call_result_views.dart';
import '../widgets/call_top_bar.dart';
import '../widgets/call_video_area.dart';
import '../widgets/sheets/call_sheets.dart';
import '../widgets/video_view_keys.dart';
import 'pre_call_screen.dart';

class CallScreen extends ConsumerWidget {
  const CallScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const CallScreen());

  void _minimise(BuildContext context, WidgetRef ref) {
    ref.read(callControllerProvider.notifier).setMinimized(true);
    Navigator.of(context).pop();
  }

  /// Back while joining cancels the join; otherwise it would finish in the
  /// background with no call screen, sending camera and mic unseen.
  void _cancelJoin(BuildContext context, WidgetRef ref) {
    unawaited(ref.read(callControllerProvider.notifier).leave());
    Navigator.of(context).pop();
  }

  void _goHome(BuildContext context) =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  void _rejoin(BuildContext context) =>
      Navigator.of(context).pushReplacement(PreCallScreen.route());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(callControllerProvider);
    final log = ref.watch(callLogProvider);

    return PopScope(
      // Back during a call minimises it; back while joining cancels it.
      canPop: !state.isBusy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (state.isLive) {
          _minimise(context, ref);
        } else {
          _cancelJoin(context, ref);
        }
      },
      child: Scaffold(
        body: switch (state.status) {
          // In Android PiP this screen stays alive but hidden (so expanding
          // returns here). Its video views must go: a second view of the
          // same person leaves the PiP window grey.
          CallStatus.inCall || CallStatus.reconnecting
              when state.isPipActive &&
                  defaultTargetPlatform == TargetPlatform.android =>
            const SizedBox.shrink(),
          CallStatus.inCall || CallStatus.reconnecting => VideoViewKeys(
            child: _LiveCallView(
              state: state,
              onMinimise: () => _minimise(context, ref),
            ),
          ),
          CallStatus.failed => CallOutcomeView(
            icon: Icons.error_outline,
            isError: true,
            title: state.failure?.label ?? PocStrings.statusFailed,
            detail: state.failureDetail,
            log: log,
            primaryLabel: PocStrings.rejoin,
            onPrimary: () => _rejoin(context),
            onHome: () => _goHome(context),
          ),
          CallStatus.ended => _EndedView(
            onRejoin: () => _rejoin(context),
            onHome: () => _goHome(context),
          ),
          CallStatus.idle || CallStatus.joining => CallProgressView(
            text: state.status.label,
            detail: state.isJoinSlow ? PocStrings.joinSlow : null,
            onCancel: state.isJoinSlow ? () => _cancelJoin(context, ref) : null,
          ),
        },
      ),
    );
  }
}

class _EndedView extends ConsumerWidget {
  const _EndedView({required this.onRejoin, required this.onHome});

  final VoidCallback onRejoin;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = ref.watch(
      statsControllerProvider.select((s) => s.call?.durationSeconds),
    );
    return CallOutcomeView(
      icon: Icons.call_end,
      title: PocStrings.statusEnded,
      detail: seconds == null
          ? null
          : '${PocStrings.callLasted} ${formatClock(Duration(seconds: seconds))}',
      log: ref.watch(callLogProvider),
      primaryLabel: PocStrings.rejoin,
      onPrimary: onRejoin,
      onHome: onHome,
    );
  }
}

class _LiveCallView extends ConsumerWidget {
  const _LiveCallView({required this.state, required this.onMinimise});

  /// Height the control bar covers, so full-bleed labels sit above it.
  static const _controlBarClearance = 132.0;
  static const _compactControlBarClearance = 88.0;

  final CallState state;
  final VoidCallback onMinimise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.orientationOf(context) == Orientation.landscape;
    final header = SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CallTopBar(
            state: state,
            onMinimise: onMinimise,
            onOpenParticipants: () => showParticipantsSheet(context),
          ),
          CallBanners(state: state),
        ],
      ),
    );
    final controls = CallControlBar(
      state: state,
      isCompact: isWide,
      onOpenChat: () => showChatSheet(context),
      onOpenMore: () => showMoreActionsSheet(context),
      onLeave: ref.read(callControllerProvider.notifier).leave,
    );

    // Landscape: keep clear of the side navigation bar / camera cut-out.
    return SafeArea(
      top: false,
      bottom: false,
      child: CallLayoutPlanner.isFullBleed(state)
          ? Stack(
              fit: StackFit.expand,
              children: [
                CallVideoArea(
                  state: state,
                  overlayBottomInset: isWide
                      ? _compactControlBarClearance
                      : _controlBarClearance,
                ),
                const _TopScrim(),
                Align(alignment: Alignment.topCenter, child: header),
                Align(alignment: Alignment.bottomCenter, child: controls),
              ],
            )
          : Column(
              children: [
                header,
                Expanded(child: CallVideoArea(state: state)),
                controls,
              ],
            ),
    );
  }
}

/// Dark fade behind the top bar so its text reads over bright video.
class _TopScrim extends StatelessWidget {
  const _TopScrim();

  static const _height = 160.0;
  static const _opacity = 0.7;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Align(
      alignment: Alignment.topCenter,
      child: IgnorePointer(
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                surface.withValues(alpha: _opacity),
                surface.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
