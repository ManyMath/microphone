/// Microphone permission hooks for the native (FFI) backend, for platforms
/// whose native layer cannot check or ask on its own.
///
/// On Android, requesting `RECORD_AUDIO` needs the app's Activity, so
/// `microphone_flutter` installs these there. macOS and iOS are answered by
/// the native library itself, and Linux and Windows do not gate capture, so
/// pure-Dart programs leave them null.
abstract final class NativePermission {
  /// Whether the app holds microphone permission. Overrides the native
  /// library's answer when set.
  static Future<bool> Function()? check;

  /// Asks the user for microphone permission and returns whether it was
  /// granted. Overrides the native library's request when set.
  static Future<bool> Function()? request;
}
