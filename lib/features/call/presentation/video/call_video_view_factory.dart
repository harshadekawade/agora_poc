import 'package:flutter/widgets.dart';

/// Builds the vendor's native video surfaces, so screens never import the SDK.
abstract interface class CallVideoViewFactory {
  Widget localCamera();

  /// [fitWholeFrame]: letterbox instead of crop (for shared screens, where
  /// cutting off edges loses content).
  Widget remote(int uid, {bool fitWholeFrame = false});
}
