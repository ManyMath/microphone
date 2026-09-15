# microphone_flutter_example

Demonstrates `microphone_flutter`: record from the microphone, watch a
live input-level meter, and stop to keep the captured WAV in memory.

## Running

```sh
flutter run -d macos    # also: -d <ios device>, -d chrome, an Android emulator
```

On macOS, iOS and the web the first recording prompts for microphone
permission. This example does not request the Android runtime permission; grant
it from the app's settings (or `adb shell pm grant`). The required platform
configuration is already in this example: `NSMicrophoneUsageDescription` and the
audio-input entitlement on macOS/iOS, and `RECORD_AUDIO` on Android.
