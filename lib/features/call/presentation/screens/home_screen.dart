import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strings/poc_strings.dart';
import '../providers/call_providers.dart';
import 'call_screen.dart';
import 'pre_call_screen.dart';

/// Stand-in for the rest of the patient app, so the in-app floating call
/// window can be tested while "browsing".
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Joining counts too, so a second "Get ready" can't open mid-join.
    final isCallLive = ref.watch(
      callControllerProvider.select((s) => s.isBusy),
    );

    return Scaffold(
      appBar: AppBar(title: const Text(PocStrings.homeTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isCallLive)
            _OngoingCallCard(
              onReturn: () {
                ref.read(callControllerProvider.notifier).setMinimized(false);
                Navigator.of(context).push(CallScreen.route());
              },
            )
          else
            _StartCallCard(
              onStart: () => Navigator.of(context).push(PreCallScreen.route()),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              PocStrings.homeBrowseHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final item in PocStrings.homeSampleItems)
            Card(
              child: ListTile(
                title: Text(item),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
        ],
      ),
    );
  }
}

class _StartCallCard extends StatelessWidget {
  const _StartCallCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(PocStrings.homeStartCall, style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(PocStrings.homeStartCallHint, style: textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.videocam),
              label: const Text(PocStrings.homeStartCall),
            ),
          ],
        ),
      ),
    );
  }
}

class _OngoingCallCard extends StatelessWidget {
  const _OngoingCallCard({required this.onReturn});

  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      color: scheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.videocam, color: scheme.onPrimaryContainer),
        title: Text(
          PocStrings.homeOngoingCall,
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
        trailing: FilledButton(
          onPressed: onReturn,
          child: const Text(PocStrings.homeReturnToCall),
        ),
      ),
    );
  }
}
