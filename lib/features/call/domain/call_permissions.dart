abstract interface class CallPermissions {
  Future<CallPermissionResult> requestCameraAndMic();

  /// Checks without asking, e.g. after the user was sent to Settings.
  Future<bool> hasCameraAndMic();

  Future<void> openSettings();
}

enum CallPermissionResult { granted, denied, permanentlyDenied }
