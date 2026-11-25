import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strings/poc_strings.dart';
import '../../domain/call_engine.dart';
import '../providers/call_providers.dart';
import '../state/call_labels.dart';
import '../state/call_state.dart';

/// Minimise, room name, timer, network bars, encryption and recording.
class CallTopBar extends ConsumerWidget {
  const CallTopBar({
    super.key,
    required this.state,
    required this.onMinimise,
    required this.onOpenParticipants,
  });

  final CallState state;
  final VoidCallback onMinimise;
  final VoidCallback onOpenParticipants;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isRecording = ref.watch(
      captureControllerProvider.select((s) => s.isRecording),
    );
    final joinedAt = state.joinedAt;
    final session = state.session;
    final worstQuality = state.uplink.bars < state.downlink.bars
        ? state.uplink
        : state.downlink;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: PocStrings.minimise,
            onPressed: onMinimise,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session?.channelId ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium,
                ),
                Row(
                  children: [
                    if (joinedAt != null)
                      CallDurationText(
                        since: joinedAt,
                        style: textTheme.labelMedium,
                      ),
                    const SizedBox(width: 8),
                    NetworkBars(quality: worstQuality),
                    if (session?.isEncrypted ?? false) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.lock, size: 14, color: scheme.primary),
                    ],
                    if (isRecording) ...[
                      const SizedBox(width: 8),
                      const _RecordingDot(),
                    ],
                  ],
                ),
                const _CallStatsLine(),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: onOpenParticipants,
            icon: const Icon(Icons.people_alt_outlined, size: 18),
            label: Text('${state.people.length + 1}'),
          ),
        ],
      ),
    );
  }
}

class _RecordingDot extends StatelessWidget {
  const _RecordingDot();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.fiber_manual_record, size: 12, color: scheme.error),
        const SizedBox(width: 2),
        Text(
          PocStrings.recording,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.error),
        ),
      ],
    );
  }
}

/// mm:ss since [since], ticking once a second.
class CallDurationText extends StatefulWidget {
  const CallDurationText({super.key, required this.since, this.style});

  final DateTime since;
  final TextStyle? style;

  @override
  State<CallDurationText> createState() => _CallDurationTextState();
}

class _CallDurationTextState extends State<CallDurationText> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    formatClock(DateTime.now().difference(widget.since)),
    style: widget.style,
  );
}

/// Four signal bars, coloured by quality.
class NetworkBars extends StatelessWidget {
  const NetworkBars({super.key, required this.quality});

  static const _maxBars = 4;
  static const _barWidth = 3.0;
  static const _barStep = 3.0;

  final CallNetworkQuality quality;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bars = quality.bars;
    final activeColor = switch (bars) {
      >= 3 => scheme.primary,
      2 => scheme.tertiary,
      _ => scheme.error,
    };
    return Tooltip(
      message: 'Network: ${quality.label}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= _maxBars; i++)
            Container(
              width: _barWidth,
              height: _barStep * (i + 1),
              margin: const EdgeInsets.only(right: 1.5),
              decoration: BoxDecoration(
                color: i <= bars ? activeColor : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}

/// Whole-call numbers (Agora onRtcStats), shown when Stats is on. Lives in
/// the top bar so it never covers a video tile's own stats.
class _CallStatsLine extends ConsumerWidget {
  const _CallStatsLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsControllerProvider);
    final call = stats.call;
    if (!stats.isOverlayVisible || call == null) return const SizedBox.shrink();
    return Text(
      '↑${call.sendKbps} ↓${call.receiveKbps} kbps · '
      'loss ${call.sendLossPercent}/${call.receiveLossPercent}% · '
      'RTT ${call.roundTripMs} ms · CPU ${call.appCpuPercent.toStringAsFixed(0)}%',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
    );
  }
}
