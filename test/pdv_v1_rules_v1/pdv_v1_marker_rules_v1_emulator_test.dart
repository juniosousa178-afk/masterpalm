import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _demoProjectId = 'demo-masterpalm-pdv-v1-r1';

/// Fase R1 — Rules V1 estoque_baixa_pagamento no Emulator demo local.
void main() {
  group('PDV V1 R1 — marker rules V1 emulator', () {
    test('pré-check host local e projectId demo', () {
      final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
      final reason = _abortReason(host);
      expect(reason, isNull, reason: reason ?? 'host inválido');
      expect(host, isNot(contains('masterpalm-58c46')));
      expect(_demoProjectId.startsWith('demo-'), isTrue);
    });

    test(
      'executa runner Node R1 com Client SDK autenticado no Emulator',
      () async {
        final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
        final reason = _abortReason(host);
        if (reason != null) {
          fail(reason);
        }

        final repoRoot = Directory.current.path;
        final runnerPath =
            '$repoRoot/test/pdv_v1_rules_v1/support/pdv_v1_marker_rules_v1_runner.mjs'
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
          reason: 'Runner R1 falhou (exit=${result.exitCode}). '
              'Matriz V1 em $_demoProjectId — host=$host.',
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
