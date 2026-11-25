/// Keeps a live call running while the app is in the background or the
/// screen is locked. Android silences the mic (and may stop the camera) of
/// a backgrounded app unless it runs an "ongoing call" foreground service.
abstract interface class CallKeepAlive {
  /// Shows the ongoing-call notification and keeps camera and mic allowed.
  /// Must be called while the app is in the foreground.
  Future<void> start({required String title, required String text});

  /// Removes the notification. Safe to call when not started.
  Future<void> stop();
}
