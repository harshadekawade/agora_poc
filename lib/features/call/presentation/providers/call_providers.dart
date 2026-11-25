import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/config/agora_config.dart';
import '../../data/agora/agora_call_capture.dart';
import '../../data/agora/agora_call_engine.dart';
import '../../data/agora/agora_call_messaging.dart';
import '../../data/agora/agora_engine_host.dart';
import '../../data/agora/agora_media_effects.dart';
import '../../data/agora/agora_pip_service.dart';
import '../../data/agora/agora_pre_call_tests.dart';
import '../../data/device_call_permissions.dart';
import '../../data/platform_call_keep_alive.dart';
import '../../data/shared_prefs_token_store.dart';
import '../../data/token_server_client.dart';
import '../../domain/call_engine.dart';
import '../../domain/call_keep_alive.dart';
import '../../domain/call_messenger.dart';
import '../../domain/call_permissions.dart';
import '../../domain/pip_service.dart';
import '../../domain/saved_token_store.dart';
import '../../domain/token_provider.dart';
import '../controllers/call_controller.dart';
import '../controllers/call_log_controller.dart';
import '../controllers/capture_controller.dart';
import '../controllers/chat_controller.dart';
import '../controllers/manual_token_controller.dart';
import '../controllers/media_settings_controller.dart';
import '../controllers/pre_call_controller.dart';
import '../controllers/speaking_controller.dart';
import '../controllers/stats_controller.dart';
import '../state/call_state.dart';
import '../state/feature_states.dart';
import '../state/pre_call_state.dart';
import '../video/agora_video_view_factory.dart';
import '../video/call_video_view_factory.dart';

// ── Configuration & infrastructure ─────────────────────────────────────────

final agoraConfigProvider = Provider<AgoraConfig>(
  (ref) => AgoraConfig.fromEnvironment(),
);

/// Agora uids are unsigned 32-bit; 0 means "assign one", so start at 1.
final uidGeneratorProvider = Provider<int Function()>((ref) {
  final random = Random.secure();
  const maxUid = 0x7FFFFFFF;
  return () => 1 + random.nextInt(maxUid - 1);
});

/// Where snapshots and recordings go. On Android this is the app's folder
/// on shared storage, so files can be pulled with adb or a file manager.
final captureDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final external = await getExternalStorageDirectory();
      if (external != null) return external;
    }
    return getApplicationDocumentsDirectory();
  },
);

/// How long a camera must stay frozen before the tile says so. Overridden
/// in tests.
final frozenNoticeDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);

/// How long to wait for any video news about someone who just joined before
/// treating them as camera-off. Agora sends nothing for a person who never
/// publishes video. Overridden in tests.
final noVideoTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// How long "Joining…" may spin before the screen says there may be no
/// connection and offers Cancel. Agora keeps retrying meanwhile. Overridden
/// in tests.
final slowJoinNoticeDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 10),
);

/// How often a live call re-announces our name and role, in case an
/// earlier announcement was lost. Overridden in tests.
final presenceHeartbeatProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 15),
);

/// A second announcement this long after a join, since the first one
/// around a join is often lost. Overridden in tests.
final presenceFollowUpProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

final tokenProviderProvider = Provider<TokenProvider>((ref) {
  final config = ref.watch(agoraConfigProvider);
  if (!config.usesTokenServer) {
    // ref.read, not watch: a new pasted token must not rebuild the call
    // and pre-call controllers that depend on this provider.
    return StaticTokenProvider(() => ref.read(manualTokenControllerProvider));
  }
  final client = http.Client();
  ref.onDispose(client.close);
  return TokenServerClient(
    baseUrl: Uri.parse(config.tokenServerUrl),
    httpClient: client,
    expireSeconds: config.tokenExpirySeconds,
  );
});

/// Provided in main() after SharedPreferences has loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main()'),
);

final savedTokenStoreProvider = Provider<SavedTokenStore>(
  (ref) => SharedPrefsTokenStore(ref.watch(sharedPreferencesProvider)),
);

final manualTokenControllerProvider =
    NotifierProvider<ManualTokenController, String>(ManualTokenController.new);

final callPermissionsProvider = Provider<CallPermissions>(
  (ref) => const DeviceCallPermissions(),
);

final callKeepAliveProvider = Provider<CallKeepAlive>(
  (ref) => const PlatformCallKeepAlive(),
);

// ── Agora adapters (only this block knows the vendor) ──────────────────────

final agoraEngineHostProvider = Provider<AgoraEngineHost>((ref) {
  final host = AgoraEngineHost();
  ref.onDispose(host.dispose);
  return host;
});

final callEngineProvider = Provider<CallEngine>(
  (ref) => AgoraCallEngine(ref.watch(agoraEngineHostProvider)),
);

final mediaEffectsProvider = Provider<MediaEffects>(
  (ref) => AgoraMediaEffects(ref.watch(agoraEngineHostProvider)),
);

final callMessagingProvider = Provider<CallMessaging>((ref) {
  final messaging = AgoraCallMessaging(ref.watch(agoraEngineHostProvider));
  ref.onDispose(messaging.dispose);
  return messaging;
});

final callCaptureProvider = Provider<CallCapture>(
  (ref) => AgoraCallCapture(ref.watch(agoraEngineHostProvider)),
);

final preCallTestsProvider = Provider<PreCallTests>(
  (ref) => AgoraPreCallTests(ref.watch(agoraEngineHostProvider)),
);

final pipServiceProvider = Provider<PipService>((ref) {
  final pip = AgoraPipService(ref.watch(agoraEngineHostProvider));
  ref.onDispose(pip.dispose);
  return pip;
});

final callVideoViewFactoryProvider = Provider<CallVideoViewFactory>(
  (ref) => AgoraVideoViewFactory(ref.watch(agoraEngineHostProvider)),
);

final callMessengerProvider = Provider<CallMessenger>(
  (ref) => CallMessenger(ref.watch(callMessagingProvider)),
);

// ── Controllers ────────────────────────────────────────────────────────────

final callLogProvider = NotifierProvider<CallLogController, List<CallLogEntry>>(
  CallLogController.new,
);

final preCallControllerProvider =
    NotifierProvider<PreCallController, PreCallState>(PreCallController.new);

final mediaSettingsControllerProvider =
    NotifierProvider<MediaSettingsController, MediaSettings>(
      MediaSettingsController.new,
    );

final callControllerProvider = NotifierProvider<CallController, CallState>(
  CallController.new,
);

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

final statsControllerProvider = NotifierProvider<StatsController, StatsState>(
  StatsController.new,
);

final captureControllerProvider =
    NotifierProvider<CaptureController, CaptureState>(CaptureController.new);

/// Volume 0–255 per uid (0 = us), updated ~3×/s. Kept apart from
/// [callControllerProvider] so only the speaking indicators rebuild.
final speakingControllerProvider =
    NotifierProvider<SpeakingController, Map<int, int>>(SpeakingController.new);
