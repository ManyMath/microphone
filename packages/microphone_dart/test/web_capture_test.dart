@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:microphone_dart/microphone_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

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

  test('stop then dispose tears down cleanly', () async {
    var rejections = 0;
    final onRejection = ((web.Event _) => rejections++).toJS;
    web.window.addEventListener('unhandledrejection', onRejection);
    addTearDown(
      () => web.window.removeEventListener('unhandledrejection', onRejection),
    );
    final recording = await Microphone.record();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await recording.stop();
    await recording.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(rejections, 0);
  });

  test('a Web Audio setup failure releases the microphone', () async {
    // Capture the stream getUserMedia opens, then make AudioContext throw.
    final mediaDevices = web.window.navigator.mediaDevices as JSObject;
    final getUserMedia = mediaDevices['getUserMedia'] as JSFunction;
    web.MediaStream? opened;
    mediaDevices['getUserMedia'] = ((JSAny? constraints) {
      final promise =
          getUserMedia.callAsFunction(mediaDevices, constraints)
              as JSPromise<web.MediaStream>;
      return promise.toDart.then((stream) => opened = stream).toJS;
    }).toJS;
    final audioContext = globalContext['AudioContext'];
    JSObject failingAudioContext() => throw StateError('no audio');
    globalContext['AudioContext'] = failingAudioContext.toJS;
    addTearDown(() {
      mediaDevices.delete('getUserMedia'.toJS);
      globalContext['AudioContext'] = audioContext;
    });

    await expectLater(Microphone.record(), throwsA(isA<CaptureException>()));
    final tracks = opened!.getTracks().toDart;
    expect(tracks, isNotEmpty);
    expect(tracks.every((t) => t.readyState == 'ended'), isTrue);
  });

  test('an unknown deviceId fails rather than using another input', () async {
    await expectLater(
      Microphone.record(deviceId: 'no-such-device'),
      throwsA(
        isA<CaptureException>().having(
          (e) => e.message,
          'message',
          contains('OverconstrainedError'),
        ),
      ),
    );
  });

  test('lists audio inputs', () async {
    expect(await Microphone.requestPermission(), isTrue);
    final devices = await Microphone.devices();
    expect(devices, isNotEmpty);
    expect(devices.every((d) => d.id.isNotEmpty), isTrue);
  });
}
