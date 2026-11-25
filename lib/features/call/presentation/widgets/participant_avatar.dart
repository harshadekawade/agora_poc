import 'package:flutter/material.dart';

import '../state/call_labels.dart';

/// Initials on a colour picked from the uid, shown when video is off.
class ParticipantAvatar extends StatelessWidget {
  const ParticipantAvatar({
    super.key,
    required this.name,
    required this.seed,
    this.radius = 32,
  });

  final String name;
  final int seed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = [
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    ];
    final (background, foreground) = palette[seed.abs() % palette.length];
    final initials = initialsOf(name);

    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: foreground,
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
