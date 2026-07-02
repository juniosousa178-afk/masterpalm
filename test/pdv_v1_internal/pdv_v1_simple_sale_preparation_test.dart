import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_canonical_json.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_simple_sale_preparation.dart';

const _txHashVector =
    '54057fe86061142af70fd516bea621352587b3f611ecb969faa8b07c90584b97';
const _snapshotHashVector =
    '1297da35da51a9e77d643d73b06db76be48a323bcd04612cb9d95c1d23421065';

PdvV1SimpleSalePreparationInput _validInput({
  String operationId = 'op-001',
  String saleId = 'op-001',
  String lojaId = 'loja-a',
  int preparedAtEpochMs = 1700000000000,
  String stockDocumentId = 'prod-001',
  int quantidade = 2,
  int saleLineCount = 1,
  int stockLineCount = 1,
  bool isNewPdvSale = true,
  bool hasCombo = false,
  bool isFiado = false,
  bool isEdicao = false,
  bool isCancelamento = false,
  bool hasVariationSelection = false,
  bool productHasVariationDefinition = false,
  bool stockShapeIsKnownSimpleDirect = true,
}) {
  return PdvV1SimpleSalePreparationInput(
    operationId: operationId,
    saleId: saleId,
    lojaId: lojaId,
    preparedAtEpochMs: preparedAtEpochMs,
    stockDocumentId: stockDocumentId,
    quantidade: quantidade,
    saleLineCount: saleLineCount,
    stockLineCount: stockLineCount,
    isNewPdvSale: isNewPdvSale,
    hasCombo: hasCombo,
    isFiado: isFiado,
    isEdicao: isEdicao,
    isCancelamento: isCancelamento,
    hasVariationSelection: hasVariationSelection,
    productHasVariationDefinition: productHasVariationDefinition,
    stockShapeIsKnownSimpleDirect: stockShapeIsKnownSimpleDirect,
  );
}

void main() {
  group('pdvV1PrepareSimpleSale', () {
    test('1. input simples válido retorna eligible', () {
      final result = pdvV1PrepareSimpleSale(_validInput());
      expect(result.isEligible, isTrue);
      expect(result.prepared, isNotNull);
      expect(result.rejectionCode, isNull);
    });

    test('2. wrapper e inner possuem operationId == saleId', () {
      final prepared = pdvV1PrepareSimpleSale(_validInput()).prepared!;
      expect(prepared.operationId, 'op-001');
      expect(prepared.saleId, 'op-001');
      expect(prepared.operationId, prepared.saleId);
      expect(prepared.preparedSnapshot['operationId'], prepared.operationId);
      expect(prepared.preparedSnapshot['saleId'], prepared.saleId);
    });

    test('3. origem serializada é exatamente pdv', () {
      final prepared = pdvV1PrepareSimpleSale(_validInput()).prepared!;
      expect(prepared.origemProtocol, 'pdv');
      expect(prepared.preparedSnapshot['origem'], 'pdv');
    });

    test('4. protocolVersion é int 1', () {
      final prepared = pdvV1PrepareSimpleSale(_validInput()).prepared!;
      expect(prepared.protocolVersion, 1);
      expect(prepared.preparedSnapshot['protocolVersion'], 1);
    });

    test('5. inner possui exatamente 8 chaves', () {
      final inner =
          pdvV1PrepareSimpleSale(_validInput()).prepared!.preparedSnapshot;
      expect(inner.keys.toSet(), {
        'protocolVersion',
        'operationId',
        'saleId',
        'lojaId',
        'origem',
        'snapshotHash',
        'txItemsHash',
        'txItems',
      });
      expect(inner.length, 8);
    });

    test('6. txItems possui exatamente uma entrada', () {
      final txItems = pdvV1PrepareSimpleSale(_validInput())
          .prepared!
          .preparedSnapshot['txItems'];
      expect(txItems, isA<List>());
      expect((txItems as List).length, 1);
    });

    test('7. item possui exatamente productId e quantidade', () {
      final item = (pdvV1PrepareSimpleSale(_validInput())
              .prepared!
              .preparedSnapshot['txItems'] as List)
          .single as Map;
      expect(item.keys.toSet(), {'productId', 'quantidade'});
      expect(item.length, 2);
    });

    test('8. vetor válido produz hashes literais esperados', () {
      final prepared = pdvV1PrepareSimpleSale(_validInput()).prepared!;
      expect(prepared.txItemsHash, _txHashVector);
      expect(prepared.snapshotHash, _snapshotHashVector);
    });

    test('9. alterar quantidade muda txItemsHash e snapshotHash', () {
      final base = pdvV1PrepareSimpleSale(_validInput()).prepared!;
      final changed =
          pdvV1PrepareSimpleSale(_validInput(quantidade: 3)).prepared!;
      expect(changed.txItemsHash, isNot(base.txItemsHash));
      expect(changed.snapshotHash, isNot(base.snapshotHash));
    });

    test('10. alterar lojaId muda snapshotHash, mas não txItemsHash', () {
      final base = pdvV1PrepareSimpleSale(_validInput()).prepared!;
      final changed =
          pdvV1PrepareSimpleSale(_validInput(lojaId: 'loja-b')).prepared!;
      expect(changed.txItemsHash, base.txItemsHash);
      expect(changed.snapshotHash, isNot(base.snapshotHash));
    });

    test('11. alterar operationId/saleId juntos muda snapshotHash', () {
      final base = pdvV1PrepareSimpleSale(_validInput()).prepared!;
      final changed = pdvV1PrepareSimpleSale(
        _validInput(operationId: 'op-002', saleId: 'op-002'),
      ).prepared!;
      expect(changed.snapshotHash, isNot(base.snapshotHash));
    });

    test('12. preparedAtEpochMs diferente não muda hashes', () {
      final base = pdvV1PrepareSimpleSale(_validInput()).prepared!;
      final changed = pdvV1PrepareSimpleSale(
        _validInput(preparedAtEpochMs: 1800000000000),
      ).prepared!;
      expect(changed.txItemsHash, base.txItemsHash);
      expect(changed.snapshotHash, base.snapshotHash);
      expect(changed.preparedAtEpochMs, 1800000000000);
    });

    test('13. operationId vazio rejeita', () {
      final result = pdvV1PrepareSimpleSale(_validInput(operationId: ''));
      expect(result.isEligible, isFalse);
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.operationIdInvalid,
      );
    });

    test('14. operationId com espaço externo rejeita', () {
      final result =
          pdvV1PrepareSimpleSale(_validInput(operationId: ' op-001'));
      expect(result.isEligible, isFalse);
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.operationIdInvalid,
      );
    });

    test('15. saleId vazio rejeita', () {
      final result = pdvV1PrepareSimpleSale(_validInput(saleId: ''));
      expect(result.isEligible, isFalse);
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.saleIdInvalid,
      );
    });

    test('16. operationId diferente de saleId rejeita', () {
      final result = pdvV1PrepareSimpleSale(
        _validInput(operationId: 'op-a', saleId: 'op-b'),
      );
      expect(result.isEligible, isFalse);
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.operationAndSaleIdMismatch,
      );
    });

    test('17. lojaId vazio ou com espaço externo rejeita', () {
      expect(
        pdvV1PrepareSimpleSale(_validInput(lojaId: '')).rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.lojaIdInvalid,
      );
      expect(
        pdvV1PrepareSimpleSale(_validInput(lojaId: ' loja-a')).rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.lojaIdInvalid,
      );
    });

    test('18. preparedAtEpochMs inválido rejeita', () {
      final result = pdvV1PrepareSimpleSale(_validInput(preparedAtEpochMs: 0));
      expect(result.isEligible, isFalse);
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.preparedAtInvalid,
      );
    });

    test('19. saleLineCount 0, 2 ou negativo rejeita', () {
      for (final count in [0, 2, -1]) {
        expect(
          pdvV1PrepareSimpleSale(_validInput(saleLineCount: count))
              .rejectionCode,
          PdvV1SimpleSalePreparationRejectionCode.saleLineCountNotOne,
        );
      }
    });

    test('20. stockLineCount 0, 2 ou negativo rejeita', () {
      for (final count in [0, 2, -1]) {
        expect(
          pdvV1PrepareSimpleSale(_validInput(stockLineCount: count))
              .rejectionCode,
          PdvV1SimpleSalePreparationRejectionCode.stockLineCountNotOne,
        );
      }
    });

    test('21. stockDocumentId vazio ou com espaço externo rejeita', () {
      expect(
        pdvV1PrepareSimpleSale(_validInput(stockDocumentId: '')).rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.stockDocumentIdInvalid,
      );
      expect(
        pdvV1PrepareSimpleSale(_validInput(stockDocumentId: ' prod-001'))
            .rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.stockDocumentIdInvalid,
      );
    });

    test('22. quantidade 0 ou negativa rejeita', () {
      for (final qty in [0, -1]) {
        expect(
          pdvV1PrepareSimpleSale(_validInput(quantidade: qty)).rejectionCode,
          PdvV1SimpleSalePreparationRejectionCode.quantidadeNotPositive,
        );
      }
    });

    test('23. isNewPdvSale false rejeita', () {
      expect(
        pdvV1PrepareSimpleSale(_validInput(isNewPdvSale: false)).rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.notNewPdvSale,
      );
    });

    test('24. hasCombo true rejeita', () {
      expect(
        pdvV1PrepareSimpleSale(_validInput(hasCombo: true)).rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.comboNotSupported,
      );
    });

    test('25. isFiado true rejeita', () {
      expect(
        pdvV1PrepareSimpleSale(_validInput(isFiado: true)).rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.fiadoNotSupported,
      );
    });

    test('26. isEdicao true rejeita', () {
      expect(
        pdvV1PrepareSimpleSale(_validInput(isEdicao: true)).rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.edicaoNotSupported,
      );
    });

    test('27. isCancelamento true rejeita', () {
      expect(
        pdvV1PrepareSimpleSale(_validInput(isCancelamento: true)).rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.cancelamentoNotSupported,
      );
    });

    test('28. hasVariationSelection true rejeita', () {
      expect(
        pdvV1PrepareSimpleSale(_validInput(hasVariationSelection: true))
            .rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.variationSelectionNotSupported,
      );
    });

    test('29. productHasVariationDefinition true rejeita', () {
      expect(
        pdvV1PrepareSimpleSale(
          _validInput(productHasVariationDefinition: true),
        ).rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.productVariationNotSupported,
      );
    });

    test('30. stockShapeIsKnownSimpleDirect false rejeita', () {
      expect(
        pdvV1PrepareSimpleSale(
          _validInput(stockShapeIsKnownSimpleDirect: false),
        ).rejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.stockShapeNotKnownSimpleDirect,
      );
    });

    test('31. resultado inelegível nunca contém prepared', () {
      final result = pdvV1PrepareSimpleSale(_validInput(isFiado: true));
      expect(result.isEligible, isFalse);
      expect(result.prepared, isNull);
    });

    test('32. três construções elegíveis idênticas retornam JSON idêntico', () {
      final jsons = List.generate(3, (_) {
        final prepared = pdvV1PrepareSimpleSale(_validInput()).prepared!;
        return pdvV1CanonicalJsonEncode(prepared.preparedSnapshot);
      });
      expect(jsons[0], jsons[1]);
      expect(jsons[1], jsons[2]);
    });

    test('33. builder não cria PdvV1JournalRecord', () {
      final source = File(
        'lib/services/pdv_v1_internal/pdv_v1_simple_sale_preparation.dart',
      ).readAsStringSync();
      expect(source.contains('PdvV1JournalRecord'), isFalse);
    });

    test('34. builder não chama Hive, executor, adapter ou Firestore', () {
      final source = File(
        'lib/services/pdv_v1_internal/pdv_v1_simple_sale_preparation.dart',
      ).readAsStringSync();
      for (final token in [
        'Hive',
        'PdvV1RemoteStockApplyOrchestrator',
        'PdvV1RemoteStockMarkerExecutor',
        'pdv_v1_infrastructure',
        'FirebaseFirestore',
        'cloud_firestore',
      ]) {
        expect(source.contains(token), isFalse, reason: token);
      }
    });
  });
}
