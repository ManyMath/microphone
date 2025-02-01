@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:microphone_cli/microphone_cli.dart';
import 'package:microphone_cli/src/backends/native/native_backend_ffi.dart';
import 'package:test/test.dart';

void main() {
  // The whole group needs the native library and a microphone, neither of which
  // CI has; it self-skips when the library cannot be loaded. On a dev host the
  // first run may prompt for microphone permission.
  final available = NativeLibrary.open() != null;

  group(
    'FFI capture (end-to-end)',
    () {
      setUp(() => Microphone.reset());
      tearDown(() => Microphone.reset());

      test('records a short clip and returns a well-formed WAV', () async {
        final backend = FfiBackend();
        expect(backend.isAvailable, isTrue);
        Microphone.registerBackend(backend, makeActive: true);

        final recording = await Microphone.record(
          format: const CaptureFormat(sampleRate: 44100, channels: 1),
        );
        expect(recording.isRecording, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 400));
        final wav = await recording.stop();

        // Header well-formed.
        expect(_ascii(wav, 0, 4), 'RIFF');
        expect(_ascii(wav, 8, 12), 'WAVE');
        expect(_ascii(wav, 36, 40), 'data');
        final view = ByteData.sublistView(wav);
        expect(view.getUint32(40, Endian.little), wav.length - 44);
        // Some audio was actually captured.
        expect(wav.length, greaterThan(44));
        expect(recording.duration, greaterThan(Duration.zero));
        await recording.dispose();
      });

      test('frames stream delivers PCM and closes on stop', () async {
        Microphone.registerBackend(FfiBackend(), makeActive: true);
        final recording = await Microphone.record();
        final chunks = <int>[];
        final sub = recording.frames.listen((c) => chunks.add(c.length));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await recording.stop();
        await sub.cancel();
        expect(chunks, isNotEmpty);
        await recording.dispose();
      });

      test('reports the format actually in effect', () async {
        Microphone.registerBackend(FfiBackend(), makeActive: true);
        final recording = await Microphone.record(
          format: const CaptureFormat(sampleRate: 44100, channels: 1),
        );
        expect(recording.format.sampleRate, greaterThan(0));
        expect(recording.format.channels, greaterThan(0));
        await recording.stop();
        await recording.dispose();
      });

      test('dispose is idempotent and stop-after-dispose is safe', () async {
        Microphone.registerBackend(FfiBackend(), makeActive: true);
        final recording = await Microphone.record();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await recording.dispose();
        await recording.dispose(); // no throw
        final wav = await recording.stop(); // no throw
        expect(_ascii(wav, 0, 4), 'RIFF');
      });
    },
    skip: available ? false : 'microphone library not built',
  );
}

String _ascii(Uint8List bytes, int start, int end) =>
    String.fromCharCodes(bytes.sublist(start, end));
