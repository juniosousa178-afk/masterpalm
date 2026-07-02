import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_errors.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';

PdvV1PreparedSnapshot _validSnapshot({
  PdvV1InternalOrigin origem = PdvV1InternalOrigin.novaVendaPdvFuture,
  bool isFiado = false,
  bool hasCombo = false,
  bool isEdicao = false,
  bool isCancelamento = false,
  String operationId = 'op-1',
  String saleId = 'sale-1',
  String lojaId = 'loja-1',
  String snapshotHash = 'snap-hash-1',
  String txItemsHash = 'tx-hash-1',
  int protocolVersion = pdvV1ProtocolVersion,
}) {
  return PdvV1PreparedSnapshot(
    protocolVersion: protocolVersion,
    operationId: operationId,
    saleId: saleId,
    lojaId: lojaId,
    origem: origem,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {
      'items': [
        {'sku': 'A', 'qty': 1}
      ]
    },
    snapshotHash: snapshotHash,
    txItemsHash: txItemsHash,
    isFiado: isFiado,
    hasCombo: hasCombo,
    isEdicao: isEdicao,
    isCancelamento: isCancelamento,
  );
}

void main() {
  group('PdvV1PreparedSnapshot', () {
    test('aceita snapshot válido e serializa reversível', () {
      final snap = _validSnapshot();
      snap.validateForFoundation7AA();
      final json = snap.toJson();
      final restored = PdvV1PreparedSnapshot.fromJson(json);
      expect(restored.toJson(), json);
      expect(restored.origemProtocol, 'pdv');
    });

    test('rejeita operationId vazio', () {
      expect(
        () => _validSnapshot(operationId: '').validateForFoundation7AA(),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('rejeita saleId vazio', () {
      expect(
        () => _validSnapshot(saleId: '').validateForFoundation7AA(),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('rejeita lojaId vazio', () {
      expect(
        () => _validSnapshot(lojaId: '').validateForFoundation7AA(),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('rejeita snapshotHash vazio', () {
      expect(
        () => _validSnapshot(snapshotHash: '').validateForFoundation7AA(),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('rejeita txItemsHash vazio', () {
      expect(
        () => _validSnapshot(txItemsHash: '').validateForFoundation7AA(),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('rejeita protocolVersion inválida', () {
      expect(
        () => _validSnapshot(protocolVersion: 2).validateForFoundation7AA(),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('rejeita fiado no escopo 7A-A', () {
      expect(
        () => _validSnapshot(isFiado: true).validateForFoundation7AA(),
        throwsA(isA<PdvV1ScopeNotSupportedError>()),
      );
    });

    test('rejeita combo no escopo 7A-A', () {
      expect(
        () => _validSnapshot(hasCombo: true).validateForFoundation7AA(),
        throwsA(isA<PdvV1ScopeNotSupportedError>()),
      );
    });

    test('rejeita edição no escopo 7A-A', () {
      expect(
        () => _validSnapshot(isEdicao: true).validateForFoundation7AA(),
        throwsA(isA<PdvV1ScopeNotSupportedError>()),
      );
    });

    test('rejeita cancelamento no escopo 7A-A', () {
      expect(
        () => _validSnapshot(isCancelamento: true).validateForFoundation7AA(),
        throwsA(isA<PdvV1ScopeNotSupportedError>()),
      );
    });

    test('rejeita origens legadas', () {
      for (final origem in PdvV1InternalOrigin.values) {
        if (origem == PdvV1InternalOrigin.novaVendaPdvFuture) continue;
        expect(
          () => _validSnapshot(origem: origem).validateForFoundation7AA(),
          throwsA(isA<PdvV1ScopeNotSupportedError>()),
        );
      }
    });

    test('fromJson falha com mapa inválido', () {
      expect(
        () => PdvV1PreparedSnapshot.fromJson({'preparedSnapshot': 'x'}),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('rejeita objeto não serializável no preparedSnapshot', () {
      expect(
        () => PdvV1PreparedSnapshot(
          protocolVersion: pdvV1ProtocolVersion,
          operationId: 'op-1',
          saleId: 'sale-1',
          lojaId: 'loja-1',
          origem: PdvV1InternalOrigin.novaVendaPdvFuture,
          preparedAtEpochMs: 1700000000000,
          preparedSnapshot: {'dt': DateTime.fromMillisecondsSinceEpoch(1)},
          snapshotHash: 'h1',
          txItemsHash: 'h2',
          isFiado: false,
          hasCombo: false,
          isEdicao: false,
          isCancelamento: false,
        ),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('mutação do mapa original não altera snapshot interno', () {
      final original = <String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'sku': 'A', 'qty': 1},
        ],
      };
      final snap = _validSnapshot().copyWithPreparedSnapshot(original);
      original['items'][0]['qty'] = 99;
      expect(snap.preparedSnapshot['items'][0]['qty'], 1);
      expect(snap.toJson()['preparedSnapshot']['items'][0]['qty'], 1);
    });

    test('mutação de lista aninhada original não altera snapshot', () {
      final nested = <dynamic>[
        <String, dynamic>{'sku': 'B'}
      ];
      final original = <String, dynamic>{'items': nested};
      final snap = PdvV1PreparedSnapshot(
        protocolVersion: pdvV1ProtocolVersion,
        operationId: 'op-1',
        saleId: 'sale-1',
        lojaId: 'loja-1',
        origem: PdvV1InternalOrigin.novaVendaPdvFuture,
        preparedAtEpochMs: 1700000000000,
        preparedSnapshot: original,
        snapshotHash: 'snap-hash-1',
        txItemsHash: 'tx-hash-1',
        isFiado: false,
        hasCombo: false,
        isEdicao: false,
        isCancelamento: false,
      );
      nested.add(<String, dynamic>{'sku': 'C'});
      expect((snap.preparedSnapshot['items'] as List).length, 1);
    });

    test('snapshot exposto é somente leitura', () {
      final snap = _validSnapshot();
      final view = snap.preparedSnapshot;
      expect(
        () => view['items'] = [],
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('toJson retorna cópia defensiva', () {
      final snap = _validSnapshot();
      final json = snap.toJson();
      (json['preparedSnapshot'] as Map)['items'] = [];
      expect(snap.preparedSnapshot.containsKey('items'), isTrue);
    });

    test('journal criado não muda após mutação externa do mapa fonte', () {
      final original = <String, dynamic>{'k': 'v'};
      final snap = PdvV1PreparedSnapshot(
        protocolVersion: pdvV1ProtocolVersion,
        operationId: 'op-j',
        saleId: 'sale-j',
        lojaId: 'loja-j',
        origem: PdvV1InternalOrigin.novaVendaPdvFuture,
        preparedAtEpochMs: 1700000000000,
        preparedSnapshot: original,
        snapshotHash: 'snap-h',
        txItemsHash: 'tx-h',
        isFiado: false,
        hasCombo: false,
        isEdicao: false,
        isCancelamento: false,
      );
      final journalJson = PdvV1JournalRecord.createInitial(
        prepared: snap,
        createdAtEpochMs: 1,
      ).toJson();
      original['k'] = 'mutado';
      expect(
        journalJson['prepared']['preparedSnapshot']['k'],
        'v',
      );
    });
  });
}

extension on PdvV1PreparedSnapshot {
  PdvV1PreparedSnapshot copyWithPreparedSnapshot(Map<String, dynamic> map) {
    return PdvV1PreparedSnapshot(
      protocolVersion: protocolVersion,
      operationId: operationId,
      saleId: saleId,
      lojaId: lojaId,
      origem: origem,
      preparedAtEpochMs: preparedAtEpochMs,
      preparedSnapshot: map,
      snapshotHash: snapshotHash,
      txItemsHash: txItemsHash,
      isFiado: isFiado,
      hasCombo: hasCombo,
      isEdicao: isEdicao,
      isCancelamento: isCancelamento,
    );
  }
}
