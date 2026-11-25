import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/widgets.dart';

import '../../data/agora/agora_engine_host.dart';
import 'call_video_view_factory.dart';

/// A fresh controller per build is fine: AgoraVideoView compares controllers
/// by value (`isSame`) and only re-binds the native view when they differ.
class AgoraVideoViewFactory implements CallVideoViewFactory {
  const AgoraVideoViewFactory(this._host);

  /// Agora's id for "my own source" in a canvas.
  static const _localCanvasUid = 0;

  final AgoraEngineHost _host;

  @override
  Widget localCamera() => AgoraVideoView(
    controller: VideoViewController(
      rtcEngine: _host.engine,
      canvas: const VideoCanvas(uid: _localCanvasUid),
    ),
  );

  @override
  Widget remote(int uid, {bool fitWholeFrame = false}) => AgoraVideoView(
    key: ValueKey((uid, fitWholeFrame)),
    controller: VideoViewController.remote(
      rtcEngine: _host.engine,
      canvas: VideoCanvas(
        uid: uid,
        renderMode: fitWholeFrame
            ? RenderModeType.renderModeFit
            : RenderModeType.renderModeHidden,
      ),
      connection: RtcConnection(
        channelId: _host.channelId,
        localUid: _host.localUid,
      ),
    ),
  );
}
