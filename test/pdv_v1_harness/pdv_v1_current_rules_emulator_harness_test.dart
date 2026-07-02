import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _demoProjectId = 'demo-masterpalm-pdv-v1-harness';

/// Valida Rules ATUAIS no Emulator demo — NÃO Rules V1 futuras.
/// Nenhum dado de produção. Nenhum pipeline V1 real.
void main() {
  group('PDV V1 — current rules emulator harness (Fase 6.4)', () {
    test('pré-check isolamento host e projectId', () {
      final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
      final skip = _skipReason(host);
      if (skip != null) {
        // ignore: avoid_print
        print('SKIP rules emulator: $skip');
        expect(true, isTrue, reason: skip);
        return;
      }
      expect(host, isNot(contains('masterpalm-58c46')));
      expect(
        host!.contains('localhost') || host.contains('127.0.0.1'),
        isTrue,
      );
    },
        skip:
            _skipReason(Platform.environment['FIRESTORE_EMULATOR_HOST']) != null
                ? 'Emulator não disponível/isolado'
                : false);

    test(
      'executa runner Node com Rules atuais no Emulator demo',
      () async {
        final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
        final skip = _skipReason(host);
        if (skip != null) {
          fail(skip);
        }

        final repoRoot = Directory.current.path;
        final runnerPath =
            '$repoRoot/test/pdv_v1_harness/support/pdv_v1_current_rules_emulator_runner.mjs'
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
          reason: 'Runner Rules Fase 6.4 falhou (exit=${result.exitCode}). '
              'Valida Rules ATUAIS em $_demoProjectId — NÃO Rules V1.',
        );
      },
      skip: _skipReason(Platform.environment['FIRESTORE_EMULATOR_HOST']) != null
          ? 'Emulator não disponível/isolado'
          : false,
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('limitações declaradas', () {
      expect(
        true,
        isTrue,
        reason: 'Valida allow/deny das Rules ATUAIS no Emulator demo. '
            'NÃO prova: Rules V1, quota produção, p95, payload wire, '
            'segurança contra cliente comprometido em escala real. '
            'Produção masterpalm-58c46 NÃO foi usada.',
      );
    });
  });
}

String? _skipReason(String? host) {
  if (host == null || host.trim().isEmpty) {
    return 'FIRESTORE_EMULATOR_HOST não definido';
  }
  if (host.contains('masterpalm-58c46')) {
    return 'Host aponta para produção';
  }
  if (!host.contains('localhost') && !host.contains('127.0.0.1')) {
    return 'Host não é localhost/127.0.0.1';
  }
  return null;
}
