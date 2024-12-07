import '../../capture_backend.dart';

/// The web capture backend (getUserMedia) is not implemented yet; returns null
/// so the silent fallback is used on the web.
CaptureBackend? createNativeBackend() => null;
