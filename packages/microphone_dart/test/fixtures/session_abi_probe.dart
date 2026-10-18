import 'package:microphone_dart/microphone_dart.dart';
import 'package:microphone_dart/src/backends/native/native_backend_ffi.dart';

Future<void> main(List<String> args) async {
  NativeLibrary.overridePath = args[0];
  final backend = FfiBackend();
  if (!backend.isAvailable) throw StateError('Fixture did not load');
  Microphone.registerBackend(backend, makeActive: true);
  try {
    await Microphone.record(
      audioSessionManagement: args[1] == 'application'
          ? AudioSessionManagement.application
          : AudioSessionManagement.automatic,
    );
    throw StateError('Fixture should return an error instead of recording');
  } on UnsupportedError catch (error) {
    print('unsupported: $error');
  } on CaptureException catch (error) {
    print('capture: $error');
  } finally {
    await Microphone.reset();
  }
}
