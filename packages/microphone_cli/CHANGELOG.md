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
- Native FFI and web capture backends follow.
