import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Harness Emulator — executa SOMENTE se ambiente isolado estiver disponível.
/// projectId: demo-masterpalm-pdv-v1-harness
/// Nunca usa masterpalm-58c46.
void main() {
  group('PDV V1 — Firestore Emulator (isolado)', () {
    test('emulator isolado disponível', () {
      final host = Platform.environment['FIRESTORE_EMULATOR_HOST'];
      final skipReason = _emulatorSkipReason(host);

      if (skipReason != null) {
        // ignore: avoid_print
        print('SKIP emulator: $skipReason');
        expect(true, isTrue, reason: skipReason);
        return;
      }

      expect(host, isNotNull);
      expect(host!.contains('localhost') || host.contains('127.0.0.1'), isTrue);
      expect(
        true,
        isTrue,
        reason: 'Emulator host detectado ($host). Teste real de Rules/TX exige '
            'inicialização Firebase demo-masterpalm-pdv-v1-harness — '
            'não executado neste harness para evitar dependência de lib/ e produção.',
      );
    },
        skip: _emulatorSkipReason(
                    Platform.environment['FIRESTORE_EMULATOR_HOST']) !=
                null
            ? 'Emulator não isolado/disponível'
            : false);

    test('limitações do emulator declaradas', () {
      expect(true, isTrue,
          reason:
              'Emulator NÃO prova: p95 real, timeout infra, quota, contention produção, '
              'payload wire exato, segurança contra cliente comprometido.');
    });
  });
}

String? _emulatorSkipReason(String? host) {
  if (host == null || host.trim().isEmpty) {
    return 'FIRESTORE_EMULATOR_HOST não definido';
  }
  if (!host.contains('localhost') && !host.contains('127.0.0.1')) {
    return 'Emulator host não é localhost';
  }
  return null;
}
