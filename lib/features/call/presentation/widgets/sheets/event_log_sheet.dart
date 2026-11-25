import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/strings/poc_strings.dart';
import '../../providers/call_providers.dart';
import '../event_log_list.dart';

class EventLogSheet extends ConsumerWidget {
  const EventLogSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(callLogProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              PocStrings.eventLog,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: EventLogList(log: log, controller: scrollController),
          ),
        ],
      ),
    );
  }
}
