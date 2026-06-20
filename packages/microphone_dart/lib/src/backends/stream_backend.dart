import 'dart:async';
import 'dart:typed_data';

import '../capture_backend.dart';
import '../capture_device.dart';
import '../capture_format.dart';
import '../file_writer.dart';
import '../recording.dart';
import '../wav.dart';

/// A capture backend fed by an external [Stream] of PCM frames.
///
/// Instead of capturing from hardware, this backend presents PCM that some
/// other part of the program already has -- decoded audio, a network stream, or
/// the mixed output of a [MixingCaptureBackend] -- as a [Recording]. Each event
/// on the source stream is a chunk of interleaved samples in [format] (signed
/// 16-bit little-endian); see [CaptureFormat].
///
/// The requested format passed to [startRecording] is ignored: an injected
/// stream is not resampled, so the [Recording] always reports the stream's own
/// [format]. Read [Recording.format] for what is actually in effect.
///
/// The source is listened to once, so this backend serves a single recording.
class StreamCaptureBackend extends CaptureBackend {
  StreamCaptureBackend({
    required Stream<Uint8List> source,
    CaptureFormat format = const CaptureFormat(),
    String name = 'stream',
    int priority = 0,
  }) : _source = source,
       _format = format,
       _name = name,
       _priority = priority;

  /// Wraps a stream of [Int16List] frames, viewing each as little-endian bytes.
  ///
  /// Dart's [Int16List] is host-endian; on the little-endian hosts Dart targets
  /// this matches [SampleFormat.int16]. The samples are not copied.
  factory StreamCaptureBackend.int16(
    Stream<Int16List> source, {
    CaptureFormat format = const CaptureFormat(),
    String name = 'stream',
    int priority = 0,
  }) => StreamCaptureBackend(
    source: source.map(
      (s) => s.buffer.asUint8List(s.offsetInBytes, s.lengthInBytes),
    ),
    format: format,
    name: name,
    priority: priority,
  );

  final Stream<Uint8List> _source;
  final CaptureFormat _format;
  final String _name;
  final int _priority;

  /// Recordings handed out by this backend, in order. Useful in tests.
  final List<StreamRecording> started = [];

  @override
  String get name => _name;

  @override
  bool get isAvailable => true;

  @override
  int get priority => _priority;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<List<CaptureDevice>> devices() async => const [
    CaptureDevice(id: 'stream', label: 'Injected PCM stream', isDefault: true),
  ];

  @override
  Future<Recording> startRecording({
    CaptureFormat format = const CaptureFormat(),
    String? deviceId,
  }) async {
    final recording = StreamRecording(_source, _format);
    started.add(recording);
    recording._start();
    return recording;
  }

  @override
  Future<void> dispose() async {}
}

/// The [Recording] returned by [StreamCaptureBackend]: it forwards and
/// accumulates the frames of the wrapped source stream.
class StreamRecording implements Recording {
  StreamRecording(this._source, this._format);

  final Stream<Uint8List> _source;
  final CaptureFormat _format;
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();

  StreamSubscription<Uint8List>? _sub;
  RecordingState _state = RecordingState.idle;
  Uint8List? _wav;

  @override
  RecordingState get state => _state;

  @override
  bool get isRecording => _state == RecordingState.recording;

  @override
  CaptureFormat get format => _format;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Uint8List get pcm => _pcm.toBytes();

  @override
  Duration get duration {
    final frames = _pcm.length ~/ _format.bytesPerFrame;
    return Duration(
      microseconds:
          frames * Duration.microsecondsPerSecond ~/ _format.sampleRate,
    );
  }

  void _start() {
    _state = RecordingState.recording;
    _sub = _source.listen(_onData, onError: _onError, onDone: _onSourceDone);
  }

  void _onData(Uint8List chunk) {
    // While paused, arriving audio is dropped so there is no silent gap.
    if (_state != RecordingState.recording) return;
    _pcm.add(chunk);
    if (!_frames.isClosed) _frames.add(chunk);
  }

  void _onError(Object error, StackTrace stack) {
    if (!_frames.isClosed) _frames.addError(error, stack);
  }

  void _onSourceDone() {
    if (_state == RecordingState.recording ||
        _state == RecordingState.paused) {
      _state = RecordingState.stopped;
    }
    if (!_frames.isClosed) _frames.close();
  }

  @override
  Future<void> pause() async {
    if (_state == RecordingState.recording) _state = RecordingState.paused;
  }

  @override
  Future<void> resume() async {
    if (_state == RecordingState.paused) _state = RecordingState.recording;
  }

  @override
  Future<Uint8List> stop() async {
    if (_state != RecordingState.disposed) {
      await _sub?.cancel();
      _sub = null;
      _state = RecordingState.stopped;
    }
    if (!_frames.isClosed) await _frames.close();
    return _wav ??= wavFromPcm(_pcm.toBytes(), _format);
  }

  @override
  Future<String> stopToFile(String path) async {
    final wav = await stop();
    await writeBytes(path, wav);
    return path;
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _state = RecordingState.disposed;
    if (!_frames.isClosed) await _frames.close();
  }
}
