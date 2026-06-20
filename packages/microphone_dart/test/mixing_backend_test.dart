import 'dart:async';
import 'dart:typed_data';

import 'package:microphone_dart/microphone_dart.dart';
import 'package:test/test.dart';

/// Packs signed 16-bit [samples] as little-endian PCM bytes.
Uint8List _pcm(List<int> samples) {
  final s = Int16List.fromList(samples);
  return s.buffer.asUint8List(s.offsetInBytes, s.lengthInBytes);
}

/// Reads little-endian S16LE [pcm] back into a list of samples.
List<int> _samples(Uint8List pcm) {
  final view = ByteData.sublistView(pcm);
  return [
    for (var o = 0; o + 2 <= pcm.length; o += 2) view.getInt16(o, Endian.little),
  ];
}

/// Lets the stream microtasks deliver pending events.
Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 10));

const _fmt = CaptureFormat(sampleRate: 8000, channels: 1);

void main() {
  group('MixingCaptureBackend', () {
    test('sums the primary and a secondary, clamped to int16', () async {
      final primary = StreamController<Uint8List>();
      final clip = StreamController<Uint8List>();
      final mixing = MixingCaptureBackend([
        StreamCaptureBackend(source: primary.stream, format: _fmt),
        StreamCaptureBackend(source: clip.stream, format: _fmt),
      ]);
      final recording = await mixing.startRecording(format: _fmt);
      final out = <int>[];
      final sub = recording.frames.listen((c) => out.addAll(_samples(c)));

      // Secondary buffers ahead of the primary clock.
      clip.add(_pcm([10, 20, 30000]));
      await _pump();
      // Primary clocks a 3-sample chunk; 30000 + 30000 clamps to 32767.
      primary.add(_pcm([1, 2, 30000]));
      await _pump();

      expect(out, [11, 22, 32767]);

      await sub.cancel();
      await recording.stop();
      await primary.close();
      await clip.close();
    });

    test('zero-fills a secondary that has no buffered audio', () async {
      final primary = StreamController<Uint8List>();
      final clip = StreamController<Uint8List>();
      final mixing = MixingCaptureBackend([
        StreamCaptureBackend(source: primary.stream, format: _fmt),
        StreamCaptureBackend(source: clip.stream, format: _fmt),
      ]);
      final recording = await mixing.startRecording(format: _fmt);
      final out = <int>[];
      final sub = recording.frames.listen((c) => out.addAll(_samples(c)));

      primary.add(_pcm([5, 6])); // secondary empty -> contributes zeros
      await _pump();

      expect(out, [5, 6]);

      await sub.cancel();
      await recording.stop();
      await primary.close();
      await clip.close();
    });

    test('output is clocked by the primary, not the secondary', () async {
      final primary = StreamController<Uint8List>();
      final clip = StreamController<Uint8List>();
      final mixing = MixingCaptureBackend([
        StreamCaptureBackend(source: primary.stream, format: _fmt),
        StreamCaptureBackend(source: clip.stream, format: _fmt),
      ]);
      final recording = await mixing.startRecording(format: _fmt);
      final out = <int>[];
      final sub = recording.frames.listen((c) => out.addAll(_samples(c)));

      // Secondary alone produces no output.
      clip.add(_pcm([100, 100, 100, 100]));
      await _pump();
      expect(out, isEmpty);

      // Primary releases two samples; the rest of the clip stays buffered.
      primary.add(_pcm([1, 1]));
      await _pump();
      expect(out, [101, 101]);

      await sub.cancel();
      await recording.stop();
      await primary.close();
      await clip.close();
    });

    test('mismatched source format throws CaptureException', () async {
      final controller = StreamController<Uint8List>();
      final mixing = MixingCaptureBackend([
        StreamCaptureBackend(
          source: controller.stream,
          format: const CaptureFormat(sampleRate: 8000),
        ),
      ]);
      await expectLater(
        mixing.startRecording(format: const CaptureFormat(sampleRate: 44100)),
        throwsA(isA<CaptureException>()),
      );
      await controller.close();
    });

    test('empty source list is rejected', () {
      expect(() => MixingCaptureBackend([]), throwsArgumentError);
    });

    test('mixes a SilentBackend primary with an injected clip', () async {
      final clip = StreamController<Uint8List>();
      final mixing = MixingCaptureBackend([
        SilentBackend(chunk: const Duration(milliseconds: 20)),
        StreamCaptureBackend(source: clip.stream, format: _fmt),
      ]);
      final recording = await mixing.startRecording(format: _fmt);

      // A long, loud clip so several primary ticks mix in non-zero audio.
      clip.add(_pcm(List<int>.filled(4000, 1000)));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final wav = await recording.stop();

      // The silent mic plus the clip is audible (some sample is non-zero).
      expect(_samples(wav.sublist(44)).any((s) => s != 0), isTrue);
      await clip.close();
    });
  });
}
