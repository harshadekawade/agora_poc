import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/strings/poc_strings.dart';
import '../../domain/call_engine.dart';
import '../../domain/call_metrics.dart';
import '../../domain/call_session.dart';
import '../controllers/pre_call_controller.dart';
import '../providers/call_providers.dart';
import '../state/call_labels.dart';
import '../state/pre_call_state.dart';
import '../widgets/participant_avatar.dart';
import '../widgets/sheets/call_sheets.dart';
import '../widgets/token_field.dart';
import 'call_screen.dart';

/// Green room: preview, name and role, device tests and call settings.
class PreCallScreen extends ConsumerStatefulWidget {
  const PreCallScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const PreCallScreen());

  @override
  ConsumerState<PreCallScreen> createState() => _PreCallScreenState();
}

class _PreCallScreenState extends ConsumerState<PreCallScreen> {
  late final TextEditingController _name;
  late final TextEditingController _channel;
  late final TextEditingController _passphrase;
  late final PreCallController _controller;
  late final AppLifecycleListener _lifecycle;
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(preCallControllerProvider.notifier);
    final state = ref.read(preCallControllerProvider);
    _name = TextEditingController(text: state.displayName);
    _channel = TextEditingController(text: state.channelId);
    _passphrase = TextEditingController(text: state.encryptionPassphrase);
    // Deferred: providers must not change during the first build.
    Future.microtask(_controller.prepare);
    // Back from Settings with camera/mic now allowed: no need to reopen.
    _lifecycle = AppLifecycleListener(onResume: _controller.recheckPermissions);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _name.dispose();
    _channel.dispose();
    _passphrase.dispose();
    if (!_isJoining) unawaited(_controller.cancel());
    super.dispose();
  }

  Future<void> _join() async {
    final session = await _controller.finish();
    if (session == null || !mounted) return;
    _isJoining = true;
    unawaited(ref.read(callControllerProvider.notifier).join(session));
    await Navigator.of(context).pushReplacement(CallScreen.route());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(preCallControllerProvider);
    final textTheme = Theme.of(context).textTheme;
    final isCallBusy = ref.watch(
      callControllerProvider.select((s) => s.isBusy),
    );
    // Our own join also makes the call busy while this screen is replaced.
    if (isCallBusy && !_isJoining) {
      return const _CallAlreadyRunning();
    }

    return Scaffold(
      appBar: AppBar(title: const Text(PocStrings.preCallTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _PreviewCard(state: state),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            onChanged: _controller.setDisplayName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: PocStrings.yourName,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _channel,
            onChanged: _controller.setChannelId,
            decoration: const InputDecoration(
              labelText: PocStrings.channel,
              border: OutlineInputBorder(),
            ),
          ),
          if (!ref.watch(agoraConfigProvider).usesTokenServer) ...[
            const SizedBox(height: 12),
            const TokenField(),
          ],
          const SizedBox(height: 12),
          SegmentedButton<ParticipantRole>(
            segments: [
              for (final role in ParticipantRole.values.reversed)
                ButtonSegment(value: role, label: Text(role.label)),
            ],
            selected: {state.role},
            onSelectionChanged: (roles) => _controller.setRole(roles.first),
          ),
          const SizedBox(height: 24),
          Text(PocStrings.sectionDevice, style: textTheme.titleMedium),
          const SizedBox(height: 8),
          _DeviceTests(state: state),
          const SizedBox(height: 24),
          Text(PocStrings.sectionCall, style: textTheme.titleMedium),
          const SizedBox(height: 4),
          _CallSettings(state: state, passphrase: _passphrase),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: state.canJoin ? _join : null,
            icon: const Icon(Icons.videocam),
            label: const Text(PocStrings.join),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the green room if a call is already joining or live.
class _CallAlreadyRunning extends ConsumerWidget {
  const _CallAlreadyRunning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text(PocStrings.preCallTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam, size: 48),
              const SizedBox(height: 16),
              const Text(
                PocStrings.preCallBlockedByCall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  ref.read(callControllerProvider.notifier).setMinimized(false);
                  Navigator.of(context).pushReplacement(CallScreen.route());
                },
                child: const Text(PocStrings.homeReturnToCall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({required this.state});

  static const _previewHeightFraction = 0.42;

  final PreCallState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(preCallControllerProvider.notifier);
    final height = MediaQuery.sizeOf(context).height * _previewHeightFraction;

    final Widget content = switch (state.status) {
      PreCallStatus.ready =>
        state.startWithCamera
            ? ref.watch(callVideoViewFactoryProvider).localCamera()
            : Center(
                child: ParticipantAvatar(
                  name: state.displayName.isEmpty ? '?' : state.displayName,
                  seed: controller.localUid,
                  radius: 44,
                ),
              ),
      PreCallStatus.failed => _PreviewFailure(state: state),
      PreCallStatus.idle || PreCallStatus.preparing => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(PocStrings.preparing),
          ],
        ),
      ),
    };

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: scheme.surfaceContainerHigh),
            content,
            if (state.isReady)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PreviewToggle(
                      isOn: state.startWithMic,
                      onIcon: Icons.mic,
                      offIcon: Icons.mic_off,
                      label: PocStrings.startMuted,
                      onPressed: controller.toggleStartWithMic,
                    ),
                    const SizedBox(width: 16),
                    _PreviewToggle(
                      isOn: state.startWithCamera,
                      onIcon: Icons.videocam,
                      offIcon: Icons.videocam_off,
                      label: PocStrings.startCameraOff,
                      onPressed: controller.toggleStartWithCamera,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewToggle extends StatelessWidget {
  const _PreviewToggle({
    required this.isOn,
    required this.onIcon,
    required this.offIcon,
    required this.label,
    required this.onPressed,
  });

  final bool isOn;
  final IconData onIcon;
  final IconData offIcon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filled(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(isOn ? onIcon : offIcon),
      style: IconButton.styleFrom(
        backgroundColor: isOn
            ? scheme.surfaceContainerHighest
            : scheme.inverseSurface,
        foregroundColor: isOn ? scheme.onSurface : scheme.onInverseSurface,
        minimumSize: const Size.square(52),
      ),
    );
  }
}

class _PreviewFailure extends ConsumerWidget {
  const _PreviewFailure({required this.state});

  final PreCallState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(preCallControllerProvider.notifier);
    final failure = state.failure;
    final detail = state.failureDetail;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
            size: 40,
          ),
          const SizedBox(height: 8),
          Text(failure?.label ?? '', textAlign: TextAlign.center),
          if (detail != null)
            Text(
              detail,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 12),
          if (failure == PreCallFailure.permissionPermanentlyDenied)
            FilledButton(
              onPressed: controller.openPermissionSettings,
              child: const Text(PocStrings.openSettings),
            )
          else if (failure != PreCallFailure.notConfigured)
            FilledButton(
              onPressed: controller.prepare,
              child: const Text(PocStrings.retry),
            ),
        ],
      ),
    );
  }
}

class _DeviceTests extends ConsumerWidget {
  const _DeviceTests({required this.state});

  final PreCallState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(preCallControllerProvider.notifier);
    final echoError = state.echoError;
    final isEchoRunning = state.echoStatus == EchoTestStatus.running;
    final isNetworkRunning = state.networkStatus == NetworkTestStatus.running;
    final quality = state.networkQuality;
    final result = state.networkResult;

    return Card.filled(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text(PocStrings.echoTest),
            subtitle: isEchoRunning
                ? const Text(PocStrings.echoTestRunning)
                : echoError == null
                ? null
                : Text(echoError, maxLines: 2),
            trailing: state.echoStatus == EchoTestStatus.starting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(isEchoRunning ? Icons.stop_circle : Icons.play_circle),
            onTap: state.isReady ? controller.toggleEchoTest : null,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.network_check),
            title: const Text(PocStrings.networkTest),
            subtitle: switch ((isNetworkRunning, quality, result)) {
              (_, _, final NetworkTestResult r) => Text(_describe(r)),
              (true, final CallNetworkQuality q, _) => Text(
                '${PocStrings.networkTestRunning} · first verdict: ${q.label}',
              ),
              (true, _, _) => const Text(PocStrings.networkTestRunning),
              _ => null,
            },
            trailing: isNetworkRunning
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_circle),
            onTap: state.isReady ? controller.toggleNetworkTest : null,
          ),
        ],
      ),
    );
  }

  static String _describe(NetworkTestResult r) => r.isComplete
      ? 'Up ${r.uplinkKbps} kbps (${r.uplinkLossPercent}% loss) · '
            'Down ${r.downlinkKbps} kbps (${r.downlinkLossPercent}% loss) · '
            'RTT ${r.roundTripMs} ms'
      : 'Incomplete: Agora could not estimate bandwidth (RTT ${r.roundTripMs} ms)';
}

class _CallSettings extends ConsumerWidget {
  const _CallSettings({required this.state, required this.passphrase});

  final PreCallState state;
  final TextEditingController passphrase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(mediaSettingsControllerProvider);
    final media = ref.read(mediaSettingsControllerProvider.notifier);
    final controller = ref.read(preCallControllerProvider.notifier);

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.high_quality_outlined),
          title: const Text(PocStrings.quality),
          subtitle: Text(settings.quality.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showQualitySheet(context),
        ),
        _SettingSwitch(
          icon: Icons.graphic_eq,
          title: PocStrings.noiseSuppression,
          subtitle: PocStrings.noiseSuppressionHint,
          value: settings.isNoiseSuppressionOn,
          onChanged: (_) => media.toggleNoiseSuppression(),
        ),
        _SettingSwitch(
          icon: Icons.blur_on,
          title: PocStrings.blur,
          subtitle: settings.isBlurSupported == false
              ? PocStrings.blurUnsupported
              : null,
          value: settings.isBlurOn,
          onChanged: settings.isBlurSupported == false
              ? null
              : (_) => media.toggleBlur(),
        ),
        _SettingSwitch(
          icon: Icons.face_retouching_natural,
          title: PocStrings.beauty,
          value: settings.isBeautyOn,
          onChanged: (_) => media.toggleBeauty(),
        ),
        _SettingSwitch(
          icon: Icons.lock_outline,
          title: PocStrings.encryption,
          subtitle: PocStrings.encryptionHint,
          value: state.isEncryptionOn,
          onChanged: (_) => controller.toggleEncryption(),
        ),
        if (state.isEncryptionOn)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextField(
              controller: passphrase,
              onChanged: controller.setEncryptionPassphrase,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: PocStrings.passphrase,
                border: OutlineInputBorder(),
              ),
            ),
          ),
      ],
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}
