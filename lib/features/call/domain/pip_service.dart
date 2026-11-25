/// System picture-in-picture (the OS floating window) for a live call.
abstract interface class PipService {
  Stream<PipStatus> get statusChanges;

  /// Sets up PiP for the current call. Returns false if the device can't do it.
  Future<bool> prepare();

  /// Tells the OS which video to show in the PiP window, and whether it may
  /// enter PiP by itself when the app goes to the background.
  Future<void> configure({
    required String channelId,
    required int localUid,
    required List<int> remoteUids,
    required bool isAutoEnterAllowed,
  });

  /// Called when the app is leaving the foreground.
  Future<void> enterOnBackground();

  /// Called when the app is back in the foreground.
  Future<void> exitOnForeground();

  /// Tears PiP down after a call. [prepare] can be called again later.
  Future<void> release();
}

enum PipStatus { active, inactive, failed }
