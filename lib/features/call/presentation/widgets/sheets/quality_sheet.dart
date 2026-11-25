import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/strings/poc_strings.dart';
import '../../../domain/call_engine.dart';
import '../../providers/call_providers.dart';
import '../../state/call_labels.dart';

class QualitySheet extends ConsumerWidget {
  const QualitySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      mediaSettingsControllerProvider.select((s) => s.quality),
    );
    final media = ref.read(mediaSettingsControllerProvider.notifier);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              PocStrings.quality,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              PocStrings.qualityBillingNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          RadioGroup<VideoQuality>(
            groupValue: current,
            onChanged: (quality) {
              if (quality != null) media.setQuality(quality);
            },
            child: Column(
              children: [
                for (final quality in VideoQuality.values)
                  RadioListTile<VideoQuality>(
                    value: quality,
                    title: Text(quality.label),
                    subtitle: Text(quality.priceBand),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
