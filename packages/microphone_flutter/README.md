# microphone_flutter

Flutter integration for [`microphone_cli`](../microphone_cli):
cross-platform microphone capture with **no system dependencies** for your users
to install.

This package builds the shared `microphone` Rust crate automatically (via
[cargokit](https://github.com/ManyMath/cargokit)) and bundles it with your app,
then re-exports the full `microphone_cli` API.

```dart
import 'package:microphone_flutter/microphone_flutter.dart';

await MicrophoneFlutter.ensureInitialized();
if (await Microphone.requestPermission()) {
  final recording = await Microphone.record();
  // ... later ...
  final wav = await recording.stop();
}
```

Building requires Rust (`rustup`). To remove even that for consumers, the repo
is set up for cargokit **precompiled binaries**:

- `native/microphone/cargokit.yaml` holds the public signing key and the
  release URL prefix.
- `.github/workflows/precompile.yml` builds and uploads signed binaries to
  `precompiled_<crate-hash>` releases on tag pushes. It needs a
  `CARGOKIT_PRIVATE_KEY` repository secret: the hex private key printed by
  `dart run build_tool gen-key` (keep it secret; never commit it).

Once a release exists, consuming builds download the matching signed binary
instead of invoking cargo; with none present, cargokit builds from source.
