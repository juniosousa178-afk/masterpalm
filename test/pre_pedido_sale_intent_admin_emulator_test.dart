import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _demoProjectId = 'demo-masterpalm-sale-intent-m33';

/// M3.3 — admin pre_pedidos + Sale Intent no Emulator (ADMIN-EM-1..5).
void main() {
  group('Sale intent MD2-E — admin pre_pedido emulator', () {
    test('pré-check host local e projectId demo', () {
      final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
      final reason = _abortReason(host);
      expect(reason, isNull, reason: reason ?? 'host inválido');
      expect(host, isNot(contains('masterpalm-58c46')));
      expect(_demoProjectId.startsWith('demo-'), isTrue);
    });

    test(
      'executa runner Node MD2-E admin pre_pedido',
      () async {
        final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
        final reason = _abortReason(host);
        if (reason != null) {
          fail(reason);
        }

        final repoRoot = Directory.current.path;
        final runnerPath =
            '$repoRoot/test/sale_intent/support/sale_intent_md2e_emulator_runner.mjs'
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
          reason: 'Runner MD2-E falhou (exit=${result.exitCode}). '
              'Matriz em $_demoProjectId — host=$host.',
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}

String? _abortReason(String? host) {
  if (host == null || host.trim().isEmpty) {
    return 'FIRESTORE_EMULATOR_HOST não definido — suba o Emulator local '
        '(firebase emulators:start --only firestore) antes deste teste.';
  }
  if (host.contains('masterpalm-58c46')) {
    return 'FIRESTORE_EMULATOR_HOST aponta para produção.';
  }
  final normalized = host.trim().toLowerCase();
  final local = normalized.startsWith('localhost:') ||
      normalized.startsWith('127.0.0.1:') ||
      normalized.startsWith('[::1]:');
  if (!local) {
    return 'FIRESTORE_EMULATOR_HOST não é local: $host';
  }
  return null;
}
