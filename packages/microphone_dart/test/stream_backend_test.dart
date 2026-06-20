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

void main() {
  group('StreamCaptureBackend', () {
    test('forwards frames and accumulates pcm', () async {
      final controller = StreamController<Uint8List>();
      final backend = StreamCaptureBackend(
        source: controller.stream,
        format: const CaptureFormat(sampleRate: 8000, channels: 1),
      );
      final recording = await backend.startRecording();
      final received = <int>[];
      final sub = recording.frames.listen((c) => received.addAll(_samples(c)));

      controller.add(_pcm([1, 2, 3]));
      controller.add(_pcm([4, 5]));
      await _pump();

      expect(received, [1, 2, 3, 4, 5]);
      expect(_samples(recording.pcm), [1, 2, 3, 4, 5]);
      expect(recording.format.sampleRate, 8000);

      final wav = await recording.stop();
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(_samples(wav.sublist(44)), [1, 2, 3, 4, 5]);

      await sub.cancel();
      await controller.close();
    });

    test('drops frames while paused', () async {
      final controller = StreamController<Uint8List>();
      final backend = StreamCaptureBackend(source: controller.stream);
      final recording = await backend.startRecording();

      controller.add(_pcm([1, 1]));
      await _pump();
      await recording.pause();
      controller.add(_pcm([9, 9])); // dropped while paused
      await _pump();
      await recording.resume();
      controller.add(_pcm([2, 2]));
      await _pump();

      expect(_samples(recording.pcm), [1, 1, 2, 2]);
      await recording.stop();
      await controller.close();
    });

    test('source completion stops the recording and closes frames', () async {
      final controller = StreamController<Uint8List>();
      final backend = StreamCaptureBackend(source: controller.stream);
      final recording = await backend.startRecording();
      var closed = false;
      recording.frames.listen((_) {}, onDone: () => closed = true);

      controller.add(_pcm([7, 7]));
      await controller.close();
      await _pump();

      expect(recording.state, RecordingState.stopped);
      expect(closed, isTrue);
    });

    test('stop is idempotent', () async {
      final controller = StreamController<Uint8List>();
      final backend = StreamCaptureBackend(source: controller.stream);
      final recording = await backend.startRecording();
      controller.add(_pcm([3, 3]));
      await _pump();
      final first = await recording.stop();
      final second = await recording.stop();
      expect(second.length, first.length);
      await controller.close();
    });

    test('int16 factory views samples as little-endian bytes', () async {
      final controller = StreamController<Int16List>();
      final backend = StreamCaptureBackend.int16(controller.stream);
      final recording = await backend.startRecording();
      controller.add(Int16List.fromList([100, -100]));
      await _pump();
      expect(_samples(recording.pcm), [100, -100]);
      await recording.stop();
      await controller.close();
    });
  });
}
