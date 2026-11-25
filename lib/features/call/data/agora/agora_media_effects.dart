import 'dart:convert';
import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:crypto/crypto.dart';

import '../../domain/call_engine.dart';
import 'agora_engine_host.dart';

class AgoraMediaEffects implements MediaEffects {
  const AgoraMediaEffects(this._host);

  // Agora's beauty values are 0.0–1.0; these are mild, natural settings.
  static const _beautyLightening = 0.6;
  static const _beautySmoothness = 0.5;
  static const _beautyRedness = 0.1;
  static const _beautySharpness = 0.3;

  final AgoraEngineHost _host;

  @override
  Future<bool> isBackgroundBlurSupported() => _host.engine
      .isFeatureAvailableOnDevice(FeatureType.videoVirtualBackground);

  @override
  Future<void> setVideoQuality(VideoQuality quality) =>
      _host.engine.setVideoEncoderConfiguration(
        VideoEncoderConfiguration(
          dimensions: VideoDimensions(
            width: quality.width,
            height: quality.height,
          ),
          frameRate: quality.frameRate,
        ),
      );

  @override
  Future<void> setNoiseSuppression(bool enabled) => _host.engine.setAINSMode(
    enabled: enabled,
    mode: AudioAinsMode.ainsModeBalanced,
  );

  @override
  Future<void> setBackgroundBlur(bool enabled) =>
      _host.engine.enableVirtualBackground(
        enabled: enabled,
        backgroundSource: const VirtualBackgroundSource(
          backgroundSourceType: BackgroundSourceType.backgroundBlur,
          blurDegree: BackgroundBlurDegree.blurDegreeHigh,
        ),
        segproperty: const SegmentationProperty(
          modelType: SegModelType.segModelAi,
        ),
      );

  @override
  Future<void> setBeauty(bool enabled) => _host.engine.setBeautyEffectOptions(
    enabled: enabled,
    options: const BeautyOptions(
      lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
      lighteningLevel: _beautyLightening,
      smoothnessLevel: _beautySmoothness,
      rednessLevel: _beautyRedness,
      sharpnessLevel: _beautySharpness,
    ),
  );

  @override
  Future<void> setAudioOnly(bool enabled) =>
      _host.engine.muteAllRemoteVideoStreams(enabled);

  /// AES-128-GCM2 (Agora's recommended mode). Key and the 32-byte salt are
  /// both derived from the passphrase, so everyone who types the same
  /// passphrase for the same channel ends up with identical settings.
  @override
  Future<void> setEncryption({
    required String passphrase,
    required String channelId,
  }) {
    if (passphrase.isEmpty) {
      return _host.engine.enableEncryption(
        enabled: false,
        config: const EncryptionConfig(),
      );
    }
    final key = sha256.convert(utf8.encode('key:$passphrase')).toString();
    final salt = Uint8List.fromList(
      sha256.convert(utf8.encode('salt:$channelId:$passphrase')).bytes,
    );
    return _host.engine.enableEncryption(
      enabled: true,
      config: EncryptionConfig(
        encryptionMode: EncryptionMode.aes128Gcm2,
        encryptionKey: key,
        encryptionKdfSalt: salt,
        datastreamEncryptionEnabled: true,
      ),
    );
  }
}
