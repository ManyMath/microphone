## Unreleased

- Bundles the native capture fixes listed in `microphone_dart`'s changelog.
- Docs: Android apps must request `RECORD_AUDIO` at runtime themselves
  (`requestPermission()` does not prompt on native platforms), the plugin needs
  Android API 26+, and precompiled binaries are not published yet.
- Requires Flutter 3.38+ (matching the Dart ^3.10 floor); the macOS pod targets
  10.15; podspec metadata filled in.
- Example app: Record is disabled while a recording starts, and capture errors
  stop the recording instead of leaving the page stuck.

## 0.0.1

- Flutter integration for `microphone_dart`: builds the shared `microphone`
  Rust crate via cargokit and bundles it. Re-exports the `microphone_dart`
  API and adds `MicrophoneFlutter.ensureInitialized()`.
- Documents the required platform permissions (Info.plist
  `NSMicrophoneUsageDescription` and the macOS audio-input entitlement on
  Apple; `RECORD_AUDIO` on Android).
- Example app with a record/stop UI and a live input-level meter.
