import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microphone_dart/platform_hooks.dart';
import 'package:microphone_dart/src/backends/native/native_backend_ffi.dart';
import 'package:microphone_flutter/src/android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('microphone_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  var granted = false;

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'hasPermission' => granted,
        'requestPermission' => granted = true,
        'devices' => [
          <Object?, Object?>{'id': 7, 'name': 'Synthetic input'},
        ],
        _ => throw MissingPluginException(),
      };
    });
    MicrophoneFlutterAndroid.registerWith();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    NativePlatform.checkPermission = null;
    NativePlatform.requestPermission = null;
    NativePlatform.devices = null;
    calls.clear();
    granted = false;
  });

  test('FFI permission queries reach the registered Android channel', () async {
    final backend = FfiBackend();
    expect(await backend.hasPermission(), isFalse);
    expect(await backend.requestPermission(), isTrue);
    expect(await backend.hasPermission(), isTrue);
    expect(calls, ['hasPermission', 'requestPermission', 'hasPermission']);
  });

  test('absent permission results remain denied', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await FfiBackend().hasPermission(), isFalse);
    expect(await FfiBackend().requestPermission(), isFalse);
  });

  test('channel failures do not grant permission', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    await expectLater(
      FfiBackend().hasPermission(),
      throwsA(isA<PlatformException>()),
    );
  });

  test('input enumeration preserves Android device identifiers', () async {
    final devices = await FfiBackend().devices();
    expect(devices.map((d) => d.id), ['default', '7']);
    expect(devices.last.label, 'Synthetic input');
    expect(calls, ['devices']);
  });
}
