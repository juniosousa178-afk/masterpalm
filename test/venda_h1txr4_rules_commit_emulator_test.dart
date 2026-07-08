// H1TX-R4 — permission-denied no commit Firestore (Rules Emulator).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';

void main() {
  group('H1TXR4 — marker payload vs Rules V1', () {
    test('buildMarkerBaixaPdvPayload respeita hasExactV1MarkerKeys (8 chaves)', () {
      final p = EstoqueTransactionService.buildMarkerBaixaPdvPayload(
        lojaId: 'loja-x',
        operationId: '33642f7f-test',
        snapshotHash: 'snap',
        txItemsHash: 'tx',
      );
      expect(p.keys.toSet(), {
        'protocolVersion',
        'origem',
        'operationId',
        'saleId',
        'lojaId',
        'baixaAplicada',
        'snapshotHash',
        'txItemsHash',
      });
      expect(p.containsKey('estornoAplicado'), isFalse);
      expect(p.containsKey('estornoAplicadoAt'), isFalse);
      expect(p.containsKey('estornoOrigem'), isFalse);
    });
  });

  group('H1TXR4 — Rules commit emulator runner', () {
    test('runner reproduz matriz RULE403 no Emulator', () async {
      final result = await Process.run(
        'npx',
        [
          '-y',
          'firebase-tools@latest',
          'emulators:exec',
          '--only',
          'firestore',
          'node tools/h1txr4_rules_commit_runner.mjs',
        ],
        runInShell: true,
        workingDirectory: Directory.current.path,
      );
      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      final out = '${result.stdout}';
      expect(out, contains('DENY  RULE403-4'));
      expect(out, contains('DENY  RULE403-5a'));
      expect(out, contains('DENY  RULE403-9 commit R8 EXATO'));
      expect(out, contains('ALLOW RULE403-10 estoque + marker V1 (sem produtos)'));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
