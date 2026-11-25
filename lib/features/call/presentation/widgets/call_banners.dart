import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strings/poc_strings.dart';
import '../providers/call_providers.dart';
import '../state/call_labels.dart';
import '../state/call_state.dart';

/// Status strips under the top bar: reconnecting, token renewal, sharing.
class CallBanners extends ConsumerWidget {
  const CallBanners({super.key, required this.state});

  final CallState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(callControllerProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.status == CallStatus.reconnecting)
          _Banner(
            icon: Icons.wifi_off,
            text: PocStrings.statusReconnecting,
            background: scheme.errorContainer,
            foreground: scheme.onErrorContainer,
          ),
        if (state.isTokenExpiring)
          _Banner(
            icon: Icons.key,
            text: PocStrings.tokenExpiring,
            background: scheme.tertiaryContainer,
            foreground: scheme.onTertiaryContainer,
          ),
        if (state.isScreenSharing && state.uplink.isWeak)
          _Banner(
            icon: Icons.network_check,
            text: PocStrings.slowUploadWhileSharing,
            background: scheme.errorContainer,
            foreground: scheme.onErrorContainer,
          ),
        if (state.isScreenSharing)
          _Banner(
            icon: Icons.screen_share,
            text: PocStrings.sharingScreen,
            background: scheme.primaryContainer,
            foreground: scheme.onPrimaryContainer,
            action: TextButton(
              onPressed: controller.toggleScreenShare,
              child: const Text(PocStrings.stopSharing),
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
    this.action,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: TextStyle(color: foreground)),
              ),
              ?action,
            ],
          ),
        ),
      ),
    );
  }
}
