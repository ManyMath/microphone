import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:microphone_flutter/microphone_flutter.dart';

void main() {
  runApp(const MicrophoneApp());
}

class MicrophoneApp extends StatelessWidget {
  const MicrophoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'microphone_cli',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const RecorderPage(),
    );
  }
}

class RecorderPage extends StatefulWidget {
  const RecorderPage({super.key});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  String _backend = '...';
  String _status = 'idle';
  Recording? _recording;
  StreamSubscription<Uint8List>? _frames;
  double _level = 0; // 0..1 live RMS level
  Uint8List? _lastWav;

  @override
  void initState() {
    super.initState();
    MicrophoneFlutter.ensureInitialized().then((name) {
      debugPrint('microphone_cli backend: $name');
      if (mounted) setState(() => _backend = name);
      // Headless self-test: when MIC_SELFTEST is set, record ~1s and log the
      // captured byte count, so emulator/simulator runs can be checked from
      // logs without driving the UI.
      if (const bool.fromEnvironment('MIC_SELFTEST') ||
          const String.fromEnvironment('MIC_SELFTEST').isNotEmpty) {
        _selfTest();
      }
    });
  }

  @override
  void dispose() {
    _frames?.cancel();
    _recording?.dispose();
    super.dispose();
  }

  /// Records ~1s and logs the result. Used for non-interactive verification on
  /// simulators/emulators via `--dart-define=MIC_SELFTEST=1`.
  Future<void> _selfTest() async {
    try {
      await Microphone.requestPermission();
      final recording = await Microphone.record();
      debugPrint('mic selftest: recording on ${recording.format}');
      await Future<void>.delayed(const Duration(seconds: 1));
      final wav = await recording.stop();
      await recording.dispose();
      debugPrint(
        'mic selftest: captured ${wav.length} bytes, '
        '${recording.duration.inMilliseconds} ms',
      );
    } on Object catch (e) {
      debugPrint('mic selftest failed: $e');
    }
  }

  Future<void> _start() async {
    if (!await Microphone.requestPermission()) {
      setState(() => _status = 'permission denied');
      return;
    }
    try {
      final recording = await Microphone.record();
      _frames = recording.frames.listen(_onFrame);
      setState(() {
        _recording = recording;
        _lastWav = null;
        _status = 'recording at ${recording.format.sampleRate} Hz';
      });
    } on Object catch (e) {
      setState(() => _status = 'error: $e');
    }
  }

  Future<void> _stop() async {
    final recording = _recording;
    if (recording == null) return;
    await _frames?.cancel();
    _frames = null;
    final wav = await recording.stop();
    await recording.dispose();
    setState(() {
      _recording = null;
      _level = 0;
      _lastWav = wav;
      _status =
          'recorded ${recording.duration.inMilliseconds} ms, ${wav.length} bytes';
    });
  }

  /// Computes a live RMS level (0..1) from a chunk of S16LE PCM.
  void _onFrame(Uint8List chunk) {
    final samples = Int16List.sublistView(chunk);
    if (samples.isEmpty) return;
    var sumSquares = 0.0;
    for (final s in samples) {
      final n = s / 32768.0;
      sumSquares += n * n;
    }
    final rms = sqrt(sumSquares / samples.length);
    if (mounted) setState(() => _level = rms.clamp(0, 1));
  }

  @override
  Widget build(BuildContext context) {
    final recording = _recording != null;
    return Scaffold(
      appBar: AppBar(title: const Text('microphone_cli')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Backend: $_backend'),
            const SizedBox(height: 8),
            Text('Status: $_status'),
            const SizedBox(height: 24),
            // Live input level.
            LinearProgressIndicator(value: _level, minHeight: 12),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FilledButton.icon(
                  onPressed: recording ? null : _start,
                  icon: const Icon(Icons.mic),
                  label: const Text('Record'),
                ),
                FilledButton.icon(
                  onPressed: recording ? _stop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_lastWav != null)
              Text(
                'Last recording: ${_lastWav!.length} bytes of WAV in memory.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
