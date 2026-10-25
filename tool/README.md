# Private microphone payload verification

Run `python3 -m unittest discover -s tool/tests -v`, then
`python3 tool/native_payload.py --config tool/payload.json --mode candidate --output /tmp/microphone-candidate`.
Use a new output directory for each run. The Flutter candidate requires microphone_dart ^0.0.2, which is not yet hosted.
Consequently `--mode hosted` currently fails dependency resolution as expected;
this is an owner publication-order prerequisite, not a packaging pass. Publish
microphone_dart0.0.2 before microphone_flutter0.0.2 in the later public phase.
Do not weaken or override that dependency to hide the missing release.
`python3 tool/hosted_dart_smoke.py --candidate /tmp/microphone-candidate --output /tmp/microphone-hosted-dart`
separately exercises published Dart0.0.1 against the candidate native library.
It does not verify the future Flutter release against hosted Dart0.0.2.
Candidate mode checks actual0.0.2 dependency constraints before extracted-path overrides.
The payload helper validates and creates actual pub archives locally; no registry publication occurs.
The pinned hidden archive flag must create an archive or the gate fails closed.

Provision Dart3.13.2, Flutter, Python3.12+, and Rust stable plus required targets.
The helper records the exact SDK/compiler and source revision. Mac/Windows debug
builds preflight the host architecture; Linux also loads the exact bundled library,
initializes and disposes a recorder, and queries permission without recording.
Windows does the same with the bundled `runner/Debug/microphone.dll`: the process
module list must contain exactly that file, a same-named DLL on PATH is refused,
and the ABI version and null-handle contracts are checked. It neither enumerates
nor opens an input device. The evidence records the library path and SHA256, and
`hosted_dart_smoke.py` accepts that Windows candidate. The gate sets
RUSTUP_WINDOWS_PATH_ADD_BIN=1 for its children only: rustup proxies installed as
symlinks cannot be started by processes that enforce redirection trust (os error
448). `.gitattributes` keeps the hash-pinned Cargokit bytes LF under
core.autocrlf; other text files in such a checkout are archived with CRLF.
Physical microphone capture, Apple interruptions/routes, and simultaneous playback
remain separate acceptance tests. A passing source build is not hardware evidence.

Private Gitea CI runs Dart/Flutter/Rust tests and candidate/hosted consumers.
Keep per-job Cargo caches isolated from developer tools. Do not install or remove
shared SDKs from CI. The workspace lockfile tracks the provisioned Flutter SDK;
it is not shipped as a consumer dependency constraint.
