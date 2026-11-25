import 'package:flutter/material.dart';

import '../../../../core/strings/poc_strings.dart';
import '../state/feature_states.dart';
import 'event_log_list.dart';

class CallProgressView extends StatelessWidget {
  const CallProgressView({
    super.key,
    required this.text,
    this.detail,
    this.onCancel,
  });

  static const _gap = 16.0;

  final String text;

  /// Extra line under [text], e.g. why it is taking long.
  final String? detail;

  /// Shows a Cancel button when set.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    final onCancel = this.onCancel;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(_gap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: _gap),
            Text(text),
            if (detail != null) ...[
              const SizedBox(height: _gap / 2),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (onCancel != null) ...[
              const SizedBox(height: _gap),
              OutlinedButton(
                onPressed: onCancel,
                child: const Text(PocStrings.cancelJoin),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared layout for "failed" and "ended": icon, message, actions, log.
class CallOutcomeView extends StatelessWidget {
  const CallOutcomeView({
    super.key,
    required this.icon,
    required this.title,
    required this.log,
    required this.onHome,
    this.detail,
    this.primaryLabel,
    this.onPrimary,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final List<CallLogEntry> log;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback onHome;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final detail = this.detail;
    final primaryLabel = this.primaryLabel;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Icon(
              icon,
              size: 56,
              color: isError ? scheme.error : scheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            if (primaryLabel != null)
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
            TextButton(
              onPressed: onHome,
              child: const Text(PocStrings.backHome),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: EventLogList(log: log),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
