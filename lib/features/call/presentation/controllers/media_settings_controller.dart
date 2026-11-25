import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/call_engine.dart';
import '../providers/call_providers.dart';
import '../state/feature_states.dart';

/// Quality and effects. Usable before the engine exists: choices are kept
/// and applied by [applyAll] once it starts.
class MediaSettingsController extends Notifier<MediaSettings> {
  late MediaEffects _effects;
  bool _isEngineReady = false;

  @override
  MediaSettings build() {
    _effects = ref.watch(mediaEffectsProvider);
    return const MediaSettings();
  }

  /// Called once the engine is initialized.
  Future<void> applyAll() async {
    _isEngineReady = true;
    final blurSupported = await _guard(
      'Blur support check',
      _effects.isBackgroundBlurSupported,
    );
    if (!ref.mounted) return;
    state = state.copyWith(isBlurSupported: blurSupported ?? false);
    _log('Background blur supported on this device: ${blurSupported ?? false}');

    await _guard(
      'Video quality',
      () => _effects.setVideoQuality(state.quality),
    );
    if (state.isNoiseSuppressionOn) {
      await _guard(
        'Noise suppression',
        () => _effects.setNoiseSuppression(true),
      );
    }
    if (state.isBlurOn && blurSupported == true) {
      await _guard('Blur', () => _effects.setBackgroundBlur(true));
    }
    if (state.isBeautyOn) {
      await _guard('Beauty', () => _effects.setBeauty(true));
    }
    if (state.isAudioOnly) {
      await _guard('Audio only', () => _effects.setAudioOnly(true));
    }
  }

  Future<void> setQuality(VideoQuality quality) => _update(
    label: 'Video quality ${quality.width}x${quality.height}',
    next: state.copyWith(quality: quality),
    apply: () => _effects.setVideoQuality(quality),
  );

  Future<void> toggleNoiseSuppression() {
    final enabled = !state.isNoiseSuppressionOn;
    return _update(
      label: 'AI noise suppression ${enabled ? 'on' : 'off'}',
      next: state.copyWith(isNoiseSuppressionOn: enabled),
      apply: () => _effects.setNoiseSuppression(enabled),
    );
  }

  Future<void> toggleBlur() {
    if (state.isBlurSupported == false) {
      _log('Background blur is not supported on this device');
      return Future.value();
    }
    final enabled = !state.isBlurOn;
    return _update(
      label: 'Background blur ${enabled ? 'on' : 'off'}',
      next: state.copyWith(isBlurOn: enabled),
      apply: () => _effects.setBackgroundBlur(enabled),
    );
  }

  Future<void> toggleBeauty() {
    final enabled = !state.isBeautyOn;
    return _update(
      label: 'Beauty filter ${enabled ? 'on' : 'off'}',
      next: state.copyWith(isBeautyOn: enabled),
      apply: () => _effects.setBeauty(enabled),
    );
  }

  Future<void> toggleAudioOnly() {
    final enabled = !state.isAudioOnly;
    return _update(
      label: 'Audio-only mode ${enabled ? 'on' : 'off'}',
      next: state.copyWith(isAudioOnly: enabled),
      apply: () => _effects.setAudioOnly(enabled),
    );
  }

  /// Applies now if the engine is running; otherwise just remembers it.
  Future<void> _update({
    required String label,
    required MediaSettings next,
    required Future<void> Function() apply,
  }) async {
    if (!_isEngineReady) {
      state = next;
      return;
    }
    try {
      await apply();
      if (!ref.mounted) return;
      state = next;
      _log(label);
    } catch (error) {
      _log('$label failed: $error');
    }
  }

  Future<T?> _guard<T>(String label, Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      _log('$label failed: $error');
      return null;
    }
  }

  void _log(String message) {
    if (!ref.mounted) return;
    ref.read(callLogProvider.notifier).add(message);
  }
}
