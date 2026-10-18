@TestOn('linux || mac-os')
library;

import 'dart:io';
import 'package:test/test.dart';

void main() {
  test(
    'optional session ABI preserves legacy loading and fails closed',
    () async {
      final temp = Directory.systemTemp.createTempSync(
        'microphone-session-abi-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      for (final current in [false, true]) {
        final library =
            '${temp.path}/${current ? 'current' : 'legacy'}.${Platform.isMacOS ? 'dylib' : 'so'}';
        final compile = await Process.run('cc', [
          Platform.isMacOS ? '-dynamiclib' : '-shared',
          '-fPIC',
          if (current) '-DSESSION_ABI',
          'test/fixtures/session_abi.c',
          '-o',
          library,
        ]);
        expect(
          compile.exitCode,
          0,
          reason: '${compile.stdout}\n${compile.stderr}',
        );
        for (final mode in ['automatic', 'application']) {
          final probe = await Process.run(Platform.resolvedExecutable, [
            'run',
            'test/fixtures/session_abi_probe.dart',
            library,
            mode,
          ]);
          expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
          expect(
            probe.stdout,
            contains(
              mode == 'automatic'
                  ? 'automatic entry'
                  : current
                  ? 'application entry'
                  : 'unsupported:',
            ),
          );
          expect(probe.stdout, isNot(contains('unexpected entry')));
        }
      }
    },
  );
}
