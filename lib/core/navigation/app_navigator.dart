import 'package:flutter/material.dart';

/// Lets app-level overlays (floating call window, mute prompts) navigate and
/// show messages, since they sit above the Navigator.
final appNavigatorKey = GlobalKey<NavigatorState>();
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();
