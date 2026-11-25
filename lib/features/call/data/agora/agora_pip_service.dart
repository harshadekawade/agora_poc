import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';

import '../../domain/pip_service.dart';
import 'agora_engine_host.dart';

/// [PipService] using Agora's AgoraPipController (added in plugin 6.6.2).
///
/// Android needs MainActivity to extend AgoraPIPFlutterActivity and
/// `supportsPictureInPicture` in the manifest. iOS needs iOS 15+ and the
/// "audio" background mode; the camera keeps running in PiP only with Apple's
/// multitasking-camera-access entitlement.
class AgoraPipService implements PipService {
  AgoraPipService(this._host);

  /// Portrait window, the shape of a phone video consult.
  static const _aspectWidth = 9;
  static const _aspectHeight = 16;
  static const _iosPreferredWidth = 360;
  static const _iosPreferredHeight = 640;

  /// Agora value for "show only close and restore buttons", which Agora
  /// recommends for calls (play/pause controls make no sense there).
  static const _iosControlStyleCloseAndRestoreOnly = 2;

  /// 0 tells the SDK to manage the native view itself.
  static const _sdkManagedView = 0;

  final AgoraEngineHost _host;
  final _status = StreamController<PipStatus>.broadcast();

  AgoraPipController? _controller;
  bool _isSupported = false;
  bool _isAutoEnterSupported = false;

  @override
  Stream<PipStatus> get statusChanges => _status.stream;

  @override
  Future<bool> prepare() async {
    if (_controller != null) return _isSupported;

    final controller = _host.engine.createPipController();
    await controller.registerPipStateChangedObserver(
      AgoraPipStateChangedObserver(onPipStateChanged: _onStateChanged),
    );
    _isSupported = await controller.pipIsSupported();
    _isAutoEnterSupported = await controller.pipIsAutoEnterSupported();
    _controller = controller;
    return _isSupported;
  }

  @override
  Future<void> configure({
    required String channelId,
    required int localUid,
    required List<int> remoteUids,
    required bool isAutoEnterAllowed,
  }) async {
    final controller = _controller;
    if (controller == null || !_isSupported) return;

    final autoEnter = _isAutoEnterSupported && isAutoEnterAllowed;
    await controller.pipSetup(switch (defaultTargetPlatform) {
      TargetPlatform.iOS => _iosOptions(
        channelId,
        localUid,
        remoteUids,
        autoEnter: autoEnter,
      ),
      _ => _androidOptions(autoEnter: autoEnter),
    });
  }

  @override
  Future<void> enterOnBackground() async {
    final controller = _controller;
    if (controller == null || !_isSupported) return;
    // When auto-enter works (Android 12+, iOS) the OS does this itself.
    // Agora's example calls pipStart only as a fallback.
    if (_isAutoEnterSupported) return;
    await controller.pipStart();
  }

  @override
  Future<void> exitOnForeground() async {
    final controller = _controller;
    if (controller == null) return;
    // On Android pipStop only sends the activity to the background, so
    // Agora's example skips it there and lets the OS restore the window.
    if (defaultTargetPlatform == TargetPlatform.android) return;
    await controller.pipStop();
  }

  @override
  Future<void> release() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    await controller.unregisterPipStateChangedObserver();
    await controller.pipDispose();
    await controller.dispose();
  }

  Future<void> dispose() async {
    await release();
    await _status.close();
  }

  void _onStateChanged(AgoraPipState state, String? error) {
    if (_status.isClosed) return;
    _status.add(switch (state) {
      AgoraPipState.pipStateStarted => PipStatus.active,
      AgoraPipState.pipStateStopped => PipStatus.inactive,
      AgoraPipState.pipStateFailed => PipStatus.failed,
    });
  }

  AgoraPipOptions _androidOptions({required bool autoEnter}) => AgoraPipOptions(
    autoEnterEnabled: autoEnter,
    aspectRatioX: _aspectWidth,
    aspectRatioY: _aspectHeight,
    seamlessResizeEnabled: true,
  );

  /// iOS draws the PiP window natively, so it must be told which stream to
  /// show: the first other person if present, else our own camera.
  AgoraPipOptions _iosOptions(
    String channelId,
    int localUid,
    List<int> remoteUids, {
    required bool autoEnter,
  }) {
    final connection = RtcConnection(channelId: channelId, localUid: localUid);
    final stream = remoteUids.isEmpty
        ? AgoraPipVideoStream(
            connection: connection,
            canvas: const VideoCanvas(
              uid: 0,
              sourceType: VideoSourceType.videoSourceCamera,
              setupMode: VideoViewSetupMode.videoViewSetupAdd,
              renderMode: RenderModeType.renderModeHidden,
              mirrorMode: VideoMirrorModeType.videoMirrorModeEnabled,
            ),
          )
        : AgoraPipVideoStream(
            connection: connection,
            canvas: VideoCanvas(
              uid: remoteUids.first,
              sourceType: VideoSourceType.videoSourceRemote,
              setupMode: VideoViewSetupMode.videoViewSetupAdd,
              renderMode: RenderModeType.renderModeHidden,
            ),
          );

    return AgoraPipOptions(
      autoEnterEnabled: autoEnter,
      sourceContentView: _sdkManagedView,
      contentView: _sdkManagedView,
      videoStreams: [stream],
      contentViewLayout: const AgoraPipContentViewLayout(row: 1, column: 1),
      preferredContentWidth: _iosPreferredWidth,
      preferredContentHeight: _iosPreferredHeight,
      controlStyle: _iosControlStyleCloseAndRestoreOnly,
    );
  }
}
