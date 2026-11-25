import 'package:flutter/material.dart';

/// Dark theme: video calls read best on a dark surround.
abstract final class PocTheme {
  static const _seedColor = Color(0xFF0F766E);

  static ThemeData dark() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
  );
}
