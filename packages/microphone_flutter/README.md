# microphone_flutter

Flutter integration for [`microphone_dart`](../microphone_dart):
cross-platform microphone capture with the goal of no system dependencies for 
users or devs to install.

This package builds the shared `microphone` Rust crate automatically (via
[cargokit](https://github.com/ManyMath/cargokit)) and bundles it with your app,
then re-exports the full `microphone_dart` API.

```dart
import 'package:microphone_flutter/microphone_flutter.dart';

await MicrophoneFlutter.ensureInitialized();
if (await Microphone.requestPermission()) {
  final recording = await Microphone.record();
  // ... later ...
  final wav = await recording.stop();
}
```

## Permissions

The microphone is a protected resource; declare it in your app:

- **macOS / iOS**: add `NSMicrophoneUsageDescription` to `Info.plist`. On macOS
  also enable the audio-input entitlement
  (`com.apple.security.device.audio-input`) for sandboxed apps.
- **Android**: add `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`
  to `AndroidManifest.xml`. Capture uses AAudio, so the plugin needs API 26+:
  set `minSdk = 26` (or higher) in your app's `build.gradle`.

On macOS and iOS the OS prompts on first capture; the web backend prompts via
getUserMedia. On native platforms `Microphone.requestPermission()` does not
prompt and always returns true, so on **Android** request `RECORD_AUDIO` at
runtime yourself (e.g. with a permissions plugin) before recording. See the
example app for the platform configuration.

## Precompiled binaries

Building requires Rust (`rustup`). cargokit can download signed precompiled
binaries instead of invoking cargo, but this repo does not publish them yet
(there is no `rust/cargokit.yaml` or release workflow), so every
build compiles the crate from source.
