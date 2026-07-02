import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _demoProjectId = 'demo-masterpalm-pdv-v1-r2';

/// Fase R2-A — operação atômica estoque + marker V1 no Emulator demo.
void main() {
  group('PDV V1 R2-A — atomic stock marker emulator', () {
    test('pré-check host local e projectId demo R2', () {
      final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
      final reason = _abortReason(host);
      expect(reason, isNull, reason: reason ?? 'host inválido');
      expect(_demoProjectId.startsWith('demo-'), isTrue);

      final runner = File(
        '${Directory.current.path}/test/pdv_v1_rules_v1/support/pdv_v1_atomic_stock_marker_runner.mjs',
      ).readAsStringSync();
      expect(runner, contains(_demoProjectId));
    });

    test(
      'executa runner Node R2-A no Emulator com Client SDK autenticado',
      () async {
        final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
        final reason = _abortReason(host);
        if (reason != null) {
          fail(reason);
        }

        final repoRoot = Directory.current.path;
        final runnerPath =
            '$repoRoot/test/pdv_v1_rules_v1/support/pdv_v1_atomic_stock_marker_runner.mjs'
                .replaceAll('\\', '/');
        expect(File(runnerPath).existsSync(), isTrue);

        final env = Map<String, String>.from(Platform.environment);
        env['FIRESTORE_EMULATOR_HOST'] = host!;

        final result = await Process.run(
          'node',
          [runnerPath],
          workingDirectory: repoRoot,
          environment: env,
        );

        if (result.stdout.toString().trim().isNotEmpty) {
          // ignore: avoid_print
          print(result.stdout);
        }
        if (result.stderr.toString().trim().isNotEmpty) {
          // ignore: avoid_print
          print(result.stderr);
        }

        expect(
          result.exitCode,
          0,
          reason: 'Runner R2-A falhou (exit=${result.exitCode}). '
              'Matriz atômica em $_demoProjectId — host=$host.',
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}

String? _abortReason(String? host) {
  if (host == null || host.trim().isEmpty) {
    return 'FIRESTORE_EMULATOR_HOST não definido';
  }
  if (host.contains('masterpalm-58c46')) {
    return 'Host aponta para produção';
  }
  final normalized = host.trim().toLowerCase();
  final local = normalized.startsWith('localhost:') ||
      normalized.startsWith('127.0.0.1:') ||
      normalized.startsWith('[::1]:');
  if (!local) {
    return 'Host não é localhost/127.0.0.1/[::1]';
  }
  return null;
}
