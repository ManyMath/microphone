import 'package:flutter/services.dart';
import 'package:microphone_dart/microphone_dart.dart';

/// Registered automatically on Android (the plugin's `dartPluginClass`): routes
/// the native backend's permission check and request through the plugin's
/// Java side, since asking for `RECORD_AUDIO` needs the app's Activity.
abstract final class MicrophoneFlutterAndroid {
  static const _channel = MethodChannel('microphone_flutter');

  static void registerWith() {
    NativePermission.check = () async =>
        await _channel.invokeMethod<bool>('hasPermission') ?? false;
    NativePermission.request = () async =>
        await _channel.invokeMethod<bool>('requestPermission') ?? false;
  }
}
