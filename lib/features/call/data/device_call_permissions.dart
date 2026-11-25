import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/call_permissions.dart';

class DeviceCallPermissions implements CallPermissions {
  const DeviceCallPermissions();

  static const _required = [Permission.camera, Permission.microphone];

  @override
  Future<CallPermissionResult> requestCameraAndMic() async {
    final statuses = await _required.request();
    // Android 12+ needs this at runtime for Bluetooth headset audio. The call
    // works without it, so a refusal doesn't block joining.
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Permission.bluetoothConnect.request();
      // Android 13+: shows the ongoing-call notification. The call service
      // runs without it; only the notification is hidden.
      await Permission.notification.request();
    }

    if (statuses.values.every((status) => status.isGranted)) {
      return CallPermissionResult.granted;
    }
    if (statuses.values.any((status) => status.isPermanentlyDenied)) {
      return CallPermissionResult.permanentlyDenied;
    }
    return CallPermissionResult.denied;
  }

  @override
  Future<bool> hasCameraAndMic() async {
    for (final permission in _required) {
      if (!await permission.isGranted) return false;
    }
    return true;
  }

  @override
  Future<void> openSettings() => openAppSettings();
}
