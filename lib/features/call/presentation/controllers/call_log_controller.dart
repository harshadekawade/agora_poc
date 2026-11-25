import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/feature_states.dart';

/// Timestamped events from every controller, shown on screen so each test
/// can be read off the device without a debugger.
class CallLogController extends Notifier<List<CallLogEntry>> {
  static const _maxEntries = 300;

  @override
  List<CallLogEntry> build() => const [];

  void add(String message) {
    final next = [...state, CallLogEntry(at: DateTime.now(), message: message)];
    state = next.length > _maxEntries
        ? next.sublist(next.length - _maxEntries)
        : next;
    debugPrint('[AgoraPOC] $message');
  }
}
