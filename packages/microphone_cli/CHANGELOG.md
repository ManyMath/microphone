# Changelog

## 0.0.1

- Initial scaffolding.
- Core API: `Microphone`, `CaptureFormat`, `Recording`, pluggable
  `CaptureBackend`s.
- `Recording` exposes both a live PCM `frames` stream and `stop`, which returns
  the capture as WAV (RIFF) bytes; `stopToFile` writes a WAV on native
  platforms.
- Pure-Dart WAV writer (`wavFromPcm`); captured audio is S16LE PCM.
- `SilentBackend` fallback that captures silence, so the API and tests run
  without a microphone. Web-safe via conditional imports.
- FFI backend that captures via the native `microphone` Rust library, draining
  S16LE PCM into the `frames` stream and an accumulating buffer. Capture works
  on macOS and iOS (CoreAudio AudioQueue input) and Android (AAudio input).
- Web capture backend (getUserMedia + Web Audio).
- `AudioLevel` (RMS/peak, with dBFS) and a `Recording.levels()` stream for live
  input metering.
