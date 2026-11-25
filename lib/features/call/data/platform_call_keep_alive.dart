import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/call_keep_alive.dart';

/// Android: starts the app's OngoingCallService (see MainActivity.kt).
/// iOS keeps the call alive through its background audio mode, so this is
/// a no-op there.
class PlatformCallKeepAlive implements CallKeepAlive {
  const PlatformCallKeepAlive();

  static const _channel = MethodChannel('qispine.poc/ongoing_call');

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> start({required String title, required String text}) async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('start', {'title': title, 'text': text});
  }

  @override
  Future<void> stop() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('stop');
  }
}
