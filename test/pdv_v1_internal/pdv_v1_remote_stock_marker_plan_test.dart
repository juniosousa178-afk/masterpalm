import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_errors.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_remote_stock_marker_models.dart';

PdvV1RemoteStockMarkerPlan _validPlan({
  String operationId = 'op-plan-r2a-1',
  String saleId = 'sale-plan-r2a-1',
  String lojaId = 'loja-plan-r2a-1',
  String snapshotHash = 'snap-plan-r2a-1',
  String txItemsHash = 'tx-plan-r2a-1',
  String stockDocumentId = 'prod-plan-r2a-1',
  int quantityToDebit = 2,
}) {
  return PdvV1RemoteStockMarkerPlan(
    operationId: operationId,
    saleId: saleId,
    lojaId: lojaId,
    origem: pdvV1OrigemProtocolValue,
    protocolVersion: pdvV1ProtocolVersion,
    snapshotHash: snapshotHash,
    txItemsHash: txItemsHash,
    stockDocumentId: stockDocumentId,
    quantityToDebit: quantityToDebit,
  );
}

void main() {
  group('PdvV1RemoteStockMarkerPlan R2-A', () {
    test('1. plan V1 válido com todos os campos obrigatórios', () {
      final plan = _validPlan();
      expect(plan.operationId, 'op-plan-r2a-1');
      expect(plan.stockQuantityField, pdvV1RemoteStockQuantityField);
    });

    test('2. operationId vazio rejeitado', () {
      expect(
        () => _validPlan(operationId: ''),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('3. saleId vazio rejeitado', () {
      expect(
        () => _validPlan(saleId: ''),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('4. lojaId vazio rejeitado', () {
      expect(
        () => _validPlan(lojaId: ''),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('5. origem diferente de pdv rejeitada', () {
      expect(
        () => PdvV1RemoteStockMarkerPlan(
          operationId: 'op-1',
          saleId: 'sale-1',
          lojaId: 'loja-1',
          origem: 'catalogo',
          protocolVersion: pdvV1ProtocolVersion,
          snapshotHash: 'snap-1',
          txItemsHash: 'tx-1',
          stockDocumentId: 'prod-1',
          quantityToDebit: 1,
        ),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('6. protocolVersion diferente de 1 rejeitada', () {
      expect(
        () => PdvV1RemoteStockMarkerPlan(
          operationId: 'op-1',
          saleId: 'sale-1',
          lojaId: 'loja-1',
          origem: pdvV1OrigemProtocolValue,
          protocolVersion: 2,
          snapshotHash: 'snap-1',
          txItemsHash: 'tx-1',
          stockDocumentId: 'prod-1',
          quantityToDebit: 1,
        ),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('7. hash vazio rejeitado', () {
      expect(
        () => _validPlan(snapshotHash: ''),
        throwsA(isA<PdvV1ValidationError>()),
      );
      expect(
        () => _validPlan(txItemsHash: ''),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('8. stockDocumentId vazio rejeitado', () {
      expect(
        () => _validPlan(stockDocumentId: ''),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('9. quantityToDebit zero rejeitada', () {
      expect(
        () => _validPlan(quantityToDebit: 0),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('10. quantityToDebit negativa rejeitada', () {
      expect(
        () => _validPlan(quantityToDebit: -1),
        throwsA(isA<PdvV1ValidationError>()),
      );
    });

    test('11. marker serializado contém exatamente 8 chaves', () {
      final marker = _validPlan().toRemoteMarkerMap();
      expect(marker.keys.toSet(), pdvV1RemoteMarkerV1Keys.toSet());
      expect(marker.keys.length, 8);
    });

    test('12. markerId é exatamente operationId', () {
      final plan = _validPlan(operationId: 'op-marker-id-r2a');
      expect(plan.toRemoteMarkerMap()['operationId'], plan.operationId);
    });

    test('13. plan é estruturalmente determinístico', () {
      final a = _validPlan();
      final b = _validPlan();
      expect(a.toDeterministicJson(), b.toDeterministicJson());
    });

    test('14. três construções idênticas produzem serialização idêntica', () {
      final jsons = List.generate(3, (_) => _validPlan().toDeterministicJson());
      expect(jsons[0], jsons[1]);
      expect(jsons[1], jsons[2]);
    });
  });
}
