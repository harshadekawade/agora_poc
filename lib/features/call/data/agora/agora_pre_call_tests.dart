import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../domain/call_engine.dart';
import 'agora_engine_host.dart';

class AgoraPreCallTests implements PreCallTests {
  const AgoraPreCallTests(this._host);

  /// Bitrate a HD 1:1 call needs each way; Agora accepts 100 000–5 000 000.
  static const _expectedBitrateBps = 1000000;

  final AgoraEngineHost _host;

  @override
  Future<void> startEchoTest({
    required String channelId,
    required String token,
    required int delaySeconds,
  }) => _host.engine.startEchoTest(
    EchoTestConfiguration(
      enableAudio: true,
      enableVideo: false,
      token: token,
      channelId: channelId,
      intervalInSeconds: delaySeconds,
    ),
  );

  @override
  Future<void> stopEchoTest() => _host.engine.stopEchoTest();

  @override
  Future<void> startNetworkTest() => _host.engine.startLastmileProbeTest(
    const LastmileProbeConfig(
      probeUplink: true,
      probeDownlink: true,
      expectedUplinkBitrate: _expectedBitrateBps,
      expectedDownlinkBitrate: _expectedBitrateBps,
    ),
  );

  @override
  Future<void> stopNetworkTest() => _host.engine.stopLastmileProbeTest();
}
