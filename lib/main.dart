import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/navigation/app_navigator.dart';
import 'core/strings/poc_strings.dart';
import 'core/theme/poc_theme.dart';
import 'features/call/presentation/host/call_overlay_host.dart';
import 'features/call/presentation/providers/call_providers.dart';
import 'features/call/presentation/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const AgoraPocApp(),
    ),
  );
}

class AgoraPocApp extends StatelessWidget {
  const AgoraPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: PocStrings.appTitle,
      theme: PocTheme.dark(),
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appMessengerKey,
      builder: (context, child) =>
          CallOverlayHost(child: child ?? const SizedBox.shrink()),
      home: const HomeScreen(),
    );
  }
}
