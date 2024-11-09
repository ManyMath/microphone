## 0.0.1

- Flutter integration for `microphone_cli`: builds the shared `microphone`
  Rust crate via cargokit and bundles it. Re-exports the `microphone_cli`
  API and adds `MicrophoneFlutter.ensureInitialized()`.
