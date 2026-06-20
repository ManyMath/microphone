import 'dart:async';
import 'dart:typed_data';

import '../capture_backend.dart';
import '../capture_device.dart';
import '../capture_format.dart';
import '../exceptions.dart';
import '../file_writer.dart';
import '../recording.dart';
import '../wav.dart';

/// A capture backend that sums several capture sources into one stream.
///
/// Each source is itself a [CaptureBackend]. On [startRecording] this starts a
/// recording on every source in the requested [CaptureFormat] and mixes their
/// frames sample-by-sample, clamped to the signed 16-bit range.
///
/// The first source is the clock: one mixed chunk is emitted per chunk it
/// delivers, with each other source contributing the samples it has buffered so
/// far (zero-filled when it has none). This models a continuous primary input
/// (a microphone) with intermittent secondary inputs (clips), and keeps output
/// flowing even when a secondary source is silent or has ended. Output stops
/// when the primary source ends.
///
/// All sources must capture in the same [CaptureFormat]; mixing does not
/// resample. A source whose actual [Recording.format] differs throws a
/// [CaptureException].
class MixingCaptureBackend extends CaptureBackend {
  MixingCaptureBackend(
    List<CaptureBackend> sources, {
    String name = 'mixing',
    int priority = 0,
  }) : _sources = List.unmodifiable(sources),
       _name = name,
       _priority = priority {
    if (_sources.isEmpty) {
      throw ArgumentError.value(sources, 'sources', 'must not be empty');
    }
  }

  final List<CaptureBackend> _sources;
  final String _name;
  final int _priority;

  /// Recordings handed out by this backend, in order. Useful in tests.
  final List<MixingRecording> started = [];

  @override
  String get name => _name;

  @override
  bool get isAvailable => true;

  @override
  int get priority => _priority;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasPermission() async {
    for (final s in _sources) {
      if (!await s.hasPermission()) return false;
    }
    return true;
  }

  @override
  Future<bool> requestPermission() async {
    var granted = true;
    for (final s in _sources) {
      if (!await s.requestPermission()) granted = false;
    }
    return granted;
  }

  @override
  Future<List<CaptureDevice>> devices() async => const [
    CaptureDevice(id: 'mixing', label: 'Mixed capture', isDefault: true),
  ];

  @override
  Future<Recording> startRecording({
    CaptureFormat format = const CaptureFormat(),
    String? deviceId,
  }) async {
    final recordings = <Recording>[];
    try {
      for (final s in _sources) {
        await s.initialize();
        final r = await s.startRecording(format: format);
        recordings.add(r);
        if (r.format != format) {
          throw CaptureException(
            'mixing source format ${r.format} does not match requested '
            '$format',
          );
        }
      }
    } on Object {
      for (final r in recordings) {
        await r.dispose();
      }
      rethrow;
    }
    final recording = MixingRecording(recordings, format);
    started.add(recording);
    recording._start();
    return recording;
  }

  @override
  Future<void> dispose() async {
    for (final s in _sources) {
      await s.dispose();
    }
  }
}

/// The [Recording] returned by [MixingCaptureBackend]: it clocks off the first
/// source and sums the rest into each emitted chunk.
class MixingRecording implements Recording {
  MixingRecording(List<Recording> sources, this._format)
    : _sources = sources,
      _pending = List<Uint8List>.filled(sources.length, Uint8List(0));

  final List<Recording> _sources;
  final CaptureFormat _format;

  // Not-yet-consumed bytes per secondary source (index 0, the primary, unused).
  final List<Uint8List> _pending;

  final List<StreamSubscription<Uint8List>> _subs = [];
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();

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
    // Buffer secondaries first so their data is available when the primary
    // clocks a mix.
    for (var i = 1; i < _sources.length; i++) {
      final idx = i;
      _subs.add(
        _sources[idx].frames.listen(
          (chunk) => _onSecondary(idx, chunk),
          onError: _onError,
        ),
      );
    }
    _subs.add(
      _sources[0].frames.listen(
        _onPrimary,
        onError: _onError,
        onDone: _onPrimaryDone,
      ),
    );
  }

  void _onPrimary(Uint8List primary) {
    // While paused, arriving audio is dropped so there is no silent gap.
    if (_state != RecordingState.recording) return;
    final mixed = _mix(primary);
    _pcm.add(mixed);
    if (!_frames.isClosed) _frames.add(mixed);
  }

  void _onSecondary(int idx, Uint8List chunk) {
    if (_state != RecordingState.recording) return;
    final prev = _pending[idx];
    final merged = Uint8List(prev.length + chunk.length);
    merged.setRange(0, prev.length, prev);
    merged.setRange(prev.length, merged.length, chunk);
    _pending[idx] = merged;
  }

  /// Sums [primary] with the buffered head of each secondary, clamped to int16.
  Uint8List _mix(Uint8List primary) {
    final n = primary.length - (primary.length % 2); // whole samples only
    final out = Uint8List(n);
    final outView = ByteData.sublistView(out);
    final pView = ByteData.sublistView(primary);

    final secViews = <ByteData>[];
    for (var i = 1; i < _sources.length; i++) {
      secViews.add(ByteData.sublistView(_pending[i]));
    }

    for (var off = 0; off < n; off += 2) {
      var acc = pView.getInt16(off, Endian.little);
      for (final sv in secViews) {
        if (off + 2 <= sv.lengthInBytes) {
          acc += sv.getInt16(off, Endian.little);
        }
      }
      if (acc > 32767) acc = 32767;
      if (acc < -32768) acc = -32768;
      outView.setInt16(off, acc, Endian.little);
    }

    // Consume the n bytes that were mixed from each secondary buffer.
    for (var i = 1; i < _sources.length; i++) {
      final pend = _pending[i];
      _pending[i] = pend.length <= n
          ? Uint8List(0)
          : Uint8List.sublistView(pend, n);
    }
    return out;
  }

  void _onError(Object error, StackTrace stack) {
    if (!_frames.isClosed) _frames.addError(error, stack);
  }

  void _onPrimaryDone() {
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
      for (final sub in _subs) {
        await sub.cancel();
      }
      _subs.clear();
      for (final r in _sources) {
        await r.stop();
      }
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
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    for (final r in _sources) {
      await r.dispose();
    }
    _state = RecordingState.disposed;
    if (!_frames.isClosed) await _frames.close();
  }
}
