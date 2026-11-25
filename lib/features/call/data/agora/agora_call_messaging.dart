import 'dart:async';
import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../domain/call_engine.dart';
import 'agora_engine_host.dart';

/// [CallMessaging] over Agora's data stream.
class AgoraCallMessaging implements CallMessaging {
  AgoraCallMessaging(this._host) {
    // A data stream belongs to one channel session; make a new one per call.
    _subscription = _host.events.listen((event) {
      if (event is CallLeft) _streamId = null;
    });
  }

  final AgoraEngineHost _host;
  late final StreamSubscription<CallEvent> _subscription;
  int? _streamId;

  @override
  Future<void> send(Uint8List bytes) async {
    final engine = _host.engine;
    final streamId = _streamId ??= await engine.createDataStream(
      const DataStreamConfig(syncWithAudio: false, ordered: true),
    );
    await engine.sendStreamMessage(
      streamId: streamId,
      data: bytes,
      length: bytes.length,
    );
  }

  Future<void> dispose() => _subscription.cancel();
}
