import 'package:flutter/material.dart';

void main() {
  runApp(const MicrophoneApp());
}

/// Placeholder example; the record/stop UI follows once the capture API lands.
class MicrophoneApp extends StatelessWidget {
  const MicrophoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('microphone_cli')),
        body: const Center(child: Text('Capture UI coming soon.')),
      ),
    );
  }
}
