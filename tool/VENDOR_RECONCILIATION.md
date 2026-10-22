# Soundboard microphone lineage

Compared Soundboard b0fa346d31d72d648a7bc427a8f695743b57d358's tracked
`microphone/` tree with canonical microphone0dbc433adb9d1b53336bcbbebe1ef925b2a65ac0.
All native Rust, capture backend, iOS session, build tooling, and example sources
match byte-for-byte. Nine package paths differ or exist only in the vendor tree.
Two additional root files, pubspec.yaml and pubspec.lock, are absent from the
vendor tree because Soundboard folded package membership into its own workspace.
Canonical workspace/lock ownership remains in microphone; Soundboard will consume
immutable package revisions instead of nesting workspaces. The package differences:

- Two changelogs describe the vendor-only permission delegate.
- The Dart barrel, Microphone class, and permission_delegate.dart expose that
  delegate, but the vendor FFI and Flutter implementations do not consume it.
  Canonical Android already uses NativePlatform and MicrophoneFlutterAndroid.
  Retain that working implementation instead of restoring a disconnected API.
- permission_delegate_test.dart and extra Flutter tests target that obsolete API.
  Port channel permission and error behavior to the canonical Android integration.
- level_test.dart adds two more odd-offset/trailing-half-sample cases. Canonical
  already tests both behaviors (existing tests at the start of that group);
  keep the canonical coverage instead of duplicating equivalent cases.
- AndroidManifest.xml declares RECORD_AUDIO; preserve the declaration in the
  canonical plugin so manifest merging retains Soundboard's existing requirement.

The Flutter tests use a synthetic method channel and do not exercise an Android
permission dialog or real microphone. NativePlatform remains integration-owned;
no application permissionDelegate compatibility is promised by published packages.
This inventory must accompany deletion of Soundboard's vendored microphone tree.
