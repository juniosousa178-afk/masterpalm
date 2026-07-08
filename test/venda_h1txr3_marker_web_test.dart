// H1TX-R3 — TypeError no transaction.set do marker (web).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';

/// Simula cloud_firestore Transaction.set linha 95: `data as Map<String, dynamic>`.
void simulateTransactionSetCast(Map payload) {
  final _ = payload as Map<String, dynamic>;
}

void main() {
  group('H1TXR3 — marker payload VM', () {
    test('buildMarkerBaixaPdvPayload retorna Map<String,dynamic>', () {
      final p = EstoqueTransactionService.buildMarkerBaixaPdvPayload(
        lojaId: 'loja-x',
        operationId: 'a4400412-op',
        snapshotHash: 'snap',
        txItemsHash: 'tx',
      );
      expect(p, isA<Map<String, dynamic>>());
      expect(p['protocolVersion'], 1);
      expect(p['baixaAplicada'], isTrue);
      expect(p['estornoAplicado'], isFalse);
      expect(p.containsKey('estornoAplicadoAt'), isFalse);
      expect(p.containsKey('estornoOrigem'), isFalse);
    });

    test('RED cast legado inline map dynamic', () {
      final legacy = Map<dynamic, dynamic>.from({
        'protocolVersion': 1,
        'origem': 'pdv',
        'operationId': 'op',
        'saleId': 'op',
        'lojaId': 'loja',
        'baixaAplicada': true,
        'estornoAplicado': false,
        'snapshotHash': 'snap',
        'txItemsHash': 'tx',
      });
      expect(
        () => simulateTransactionSetCast(legacy),
        throwsA(isA<TypeError>()),
      );
    });

    test('GREEN payload tipado nao lanca', () {
      final p = EstoqueTransactionService.buildMarkerBaixaPdvPayload(
        lojaId: 'loja-x',
        operationId: 'op',
        snapshotHash: 'snap',
        txItemsHash: 'tx',
      );
      expect(() => simulateTransactionSetCast(p), returnsNormally);
    });
  });

  group('H1TXR3 — dart2js probe', () {
    test('probe R3 confirma TypeError no cast legado', () async {
      final result = await Process.run(
        'node',
        ['tools/h1txr3_marker_probe.js'],
        runInShell: true,
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, 0);
      final out = '${result.stdout}';
      expect(out, contains('RED-R3 inline marker JsLinkedHashMap cast: ERR'));
      expect(out, contains('TypeError'));
      expect(out, contains('GREEN marker Map<String,dynamic> sem delete: OK'));
    });
  });
}
