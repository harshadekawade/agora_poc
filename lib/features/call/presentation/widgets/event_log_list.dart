import 'package:flutter/material.dart';

import '../state/call_labels.dart';
import '../state/feature_states.dart';

/// Newest-first list of engine and app events.
class EventLogList extends StatelessWidget {
  const EventLogList({super.key, required this.log, this.controller});

  final List<CallLogEntry> log;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: Theme.of(context).colorScheme.onSurface,
    );
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: log.length,
      itemBuilder: (context, index) {
        final entry = log[log.length - 1 - index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text('${entry.timeLabel}  ${entry.message}', style: style),
        );
      },
    );
  }
}
