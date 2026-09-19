@TestOn('browser')
library;

import 'package:microphone_dart/microphone_dart.dart';
import 'package:test/test.dart';

// Runs against Chrome's fake capture device (see dart_test.yaml):
//   dart test -p chrome
void main() {
  setUp(Microphone.reset);
  tearDown(Microphone.reset);

  test('the web backend is selected by default', () {
    expect(Microphone.backend.name, 'web');
  });

  test('records a clip and returns a well-formed WAV', () async {
    final recording = await Microphone.record();
    final chunks = <int>[];
    recording.frames.listen((c) => chunks.add(c.length));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final wav = await recording.stop();
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(wav.length, greaterThan(44));
    expect(chunks, isNotEmpty);
    expect(recording.duration, greaterThan(Duration.zero));
    await recording.dispose();
  });

  test('pause drops audio and resume continues', () async {
    final recording = await Microphone.record();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await recording.pause();
    final atPause = recording.pcm.length;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(recording.pcm.length, atPause);
    await recording.resume();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(recording.pcm.length, greaterThan(atPause));
    await recording.stop();
    await recording.dispose();
  });

  test('lists audio inputs', () async {
    expect(await Microphone.requestPermission(), isTrue);
    final devices = await Microphone.devices();
    expect(devices, isNotEmpty);
    expect(devices.every((d) => d.id.isNotEmpty), isTrue);
  });
}
