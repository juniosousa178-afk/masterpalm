import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_simple_sale_pilot_mapper.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_simple_sale_preparation.dart';

const _preparedAtValid = 1700000000000;

Produto _simpleProduct({
  String idFirebase = 'prod-001',
  String tipoProduto = 'simples',
  Map<String, dynamic>? variacoes,
  Map<String, int> estoquePorTamanho = const {},
  List<Map<String, dynamic>>? itensCombo,
}) {
  return Produto(
    nome: 'Produto teste',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 20,
    precoFinal: 20,
    quantidade: 10,
    precoUnitario: 20,
    categoria: 'cat',
    dataEntrada: DateTime.fromMillisecondsSinceEpoch(0),
    idFirebase: idFirebase,
    lojaId: 'loja-a',
    tipoProduto: tipoProduto,
    variacoes: variacoes,
    estoquePorTamanho: estoquePorTamanho,
    itensCombo: itensCombo,
  );
}

VendaItem _saleItem({
  int quantidade = 2,
  String tamanho = '',
  String cor = '',
  String extraValor = '',
  String? productId,
}) {
  return VendaItem(
    produtoNome: 'Produto teste',
    quantidade: quantidade,
    precoUnitario: 20,
    tamanho: tamanho,
    cor: cor,
    extraValor: extraValor,
    productId: productId,
    lojaId: 'loja-a',
  );
}

PdvV1SimpleSalePilotContext _validContext({
  PdvV1SimpleSalePilotOrigin origin = PdvV1SimpleSalePilotOrigin.novaVendaModal,
  String operationId = 'op-001',
  String saleId = 'op-001',
  String lojaId = 'loja-a',
  int preparedAtEpochMs = _preparedAtValid,
  List<VendaItem>? saleItems,
  List<VendaItem>? stockItems,
  Produto? resolvedProduct,
  bool isFiado = false,
  bool hasComboSelection = false,
  bool isEdicao = false,
  bool isCancelamento = false,
}) {
  final item = _saleItem();
  return PdvV1SimpleSalePilotContext(
    origin: origin,
    operationId: operationId,
    saleId: saleId,
    lojaId: lojaId,
    preparedAtEpochMs: preparedAtEpochMs,
    saleItems: saleItems ?? [item],
    stockItems: stockItems ?? [item],
    resolvedProduct: resolvedProduct ?? _simpleProduct(),
    isFiado: isFiado,
    hasComboSelection: hasComboSelection,
    isEdicao: isEdicao,
    isCancelamento: isCancelamento,
  );
}

void main() {
  group('pdvV1MapSimpleSalePilot', () {
    test('1. venda simples válida seleciona V1 com preparation elegível', () {
      final stockItem = _saleItem(quantidade: 2);
      final result = pdvV1MapSimpleSalePilot(
        _validContext(saleItems: [stockItem], stockItems: [stockItem]),
      );

      expect(result.kind, PdvV1SimpleSalePilotSelectionKind.selectedForV1);
      expect(result.rejectionCode, isNull);
      expect(result.preparation, isNotNull);
      expect(result.preparation!.origemProtocol, 'pdv');

      final txItem = (result.preparation!.preparedSnapshot['txItems'] as List)
          .single as Map;
      expect(txItem['productId'], 'prod-001');
      expect(txItem['quantidade'], 2);
    });

    test('2. origens não permitidas retornam unsupportedOrigin', () {
      for (final origin in [
        PdvV1SimpleSalePilotOrigin.pedidoPublico,
        PdvV1SimpleSalePilotOrigin.orderReview,
        PdvV1SimpleSalePilotOrigin.catalogo,
        PdvV1SimpleSalePilotOrigin.posPagamento,
        PdvV1SimpleSalePilotOrigin.webhookPagamento,
        PdvV1SimpleSalePilotOrigin.unknown,
      ]) {
        final result = pdvV1MapSimpleSalePilot(_validContext(origin: origin));
        expect(result.kind, PdvV1SimpleSalePilotSelectionKind.remainsLegacy);
        expect(
          result.rejectionCode,
          PdvV1SimpleSalePilotRejectionCode.unsupportedOrigin,
        );
        expect(result.preparation, isNull);
      }
    });

    test('3. isFiado verdadeiro rejeita', () {
      final result = pdvV1MapSimpleSalePilot(_validContext(isFiado: true));
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.fiadoNotSupported,
      );
      expect(result.preparation, isNull);
    });

    test('4. hasComboSelection verdadeiro rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(hasComboSelection: true),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.comboNotSupported,
      );
    });

    test('5. produto ehCombo rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(resolvedProduct: _simpleProduct(tipoProduto: 'combo')),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.comboNotSupported,
      );
    });

    test('6. isEdicao verdadeiro rejeita', () {
      final result = pdvV1MapSimpleSalePilot(_validContext(isEdicao: true));
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.edicaoNotSupported,
      );
    });

    test('7. isCancelamento verdadeiro rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(isCancelamento: true),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.cancelamentoNotSupported,
      );
    });

    test('8. saleItems vazio, dois ou mais rejeitam saleLineCountNotOne', () {
      final item = _saleItem();
      for (final saleItems in [
        <VendaItem>[],
        [item, item],
        [item, item, item],
      ]) {
        final result = pdvV1MapSimpleSalePilot(
          _validContext(saleItems: saleItems, stockItems: [item]),
        );
        expect(
          result.rejectionCode,
          PdvV1SimpleSalePilotRejectionCode.saleLineCountNotOne,
        );
      }
    });

    test('9. stockItems vazio, dois ou mais rejeitam stockLineCountNotOne', () {
      final item = _saleItem();
      for (final stockItems in [
        <VendaItem>[],
        [item, item],
        [item, item, item],
      ]) {
        final result = pdvV1MapSimpleSalePilot(
          _validContext(saleItems: [item], stockItems: stockItems),
        );
        expect(
          result.rejectionCode,
          PdvV1SimpleSalePilotRejectionCode.stockLineCountNotOne,
        );
      }
    });

    test('10. tamanho concreto preenchido rejeita', () {
      final item = _saleItem(tamanho: 'M');
      final result = pdvV1MapSimpleSalePilot(
        _validContext(saleItems: [item], stockItems: [item]),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.variationSelectionNotSupported,
      );
    });

    test('11. cor concreta preenchida rejeita', () {
      final item = _saleItem(cor: 'Azul');
      final result = pdvV1MapSimpleSalePilot(
        _validContext(saleItems: [item], stockItems: [item]),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.variationSelectionNotSupported,
      );
    });

    test('12. extraValor concreto preenchido rejeita', () {
      final item = _saleItem(extraValor: 'A');
      final result = pdvV1MapSimpleSalePilot(
        _validContext(saleItems: [item], stockItems: [item]),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.variationSelectionNotSupported,
      );
    });

    test('13. product.usaVariacoes verdadeiro rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(
          resolvedProduct: _simpleProduct(
            variacoes: {
              'M': {'Azul': 1},
            },
          ),
        ),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported,
      );
    });

    test('14. product.variacoes não vazias rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(
          resolvedProduct: _simpleProduct(
            variacoes: {
              'sem-tamanho': {'Azul': 1},
            },
          ),
        ),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported,
      );
    });

    test('15. estoquePorTamanho com chave técnica rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(
          resolvedProduct: _simpleProduct(
            estoquePorTamanho: {'sem-tamanho': 5},
          ),
        ),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.stockShapeNotKnownSimpleDirect,
      );
    });

    test('16. temEstoquePorTamanhoComTamanhoReal rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(
          resolvedProduct: _simpleProduct(estoquePorTamanho: {'18': 3}),
        ),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.stockShapeNotKnownSimpleDirect,
      );
    });

    test('17. temVariacaoSoloTamanho rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(
          resolvedProduct: _simpleProduct(variacoes: {'M': <String, int>{}}),
        ),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported,
      );
    });

    test('18. temVariacaoSoloCor rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(
          resolvedProduct: _simpleProduct(
            variacoes: {
              'sem-tamanho': {'Azul': 1},
            },
          ),
        ),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported,
      );
    });

    test('19. temVariacaoTamanhoECor rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(
          resolvedProduct: _simpleProduct(
            variacoes: {
              'M': {'Azul': 1},
            },
          ),
        ),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported,
      );
    });

    test('20. exigeSelecaoTamanhoNaVenda rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(
          resolvedProduct: _simpleProduct(estoquePorTamanho: {'P': 2}),
        ),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.stockShapeNotKnownSimpleDirect,
      );
    });

    test('21. itensCombo não vazio rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(
          resolvedProduct: _simpleProduct(
            itensCombo: [
              {'nome': 'Comp', 'quantidade': 1},
            ],
          ),
        ),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported,
      );
    });

    test('22. idFirebase vazio rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(resolvedProduct: _simpleProduct(idFirebase: '')),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.stockDocumentIdInvalid,
      );
    });

    test('23. idFirebase com espaço externo rejeita', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(resolvedProduct: _simpleProduct(idFirebase: ' prod-001')),
      );
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.stockDocumentIdInvalid,
      );
    });

    test('24. item.productId divergente não substitui idFirebase canônico', () {
      final stockItem = _saleItem(quantidade: 2, productId: 'outro-id');
      final result = pdvV1MapSimpleSalePilot(
        _validContext(
          saleItems: [stockItem],
          stockItems: [stockItem],
          resolvedProduct: _simpleProduct(idFirebase: 'prod-001'),
        ),
      );
      expect(result.kind, PdvV1SimpleSalePilotSelectionKind.selectedForV1);
      final txItem = (result.preparation!.preparedSnapshot['txItems'] as List)
          .single as Map;
      expect(txItem['productId'], 'prod-001');
    });

    test('25. quantidade zero ou negativa rejeita', () {
      for (final qtd in [0, -1]) {
        final item = _saleItem(quantidade: qtd);
        final result = pdvV1MapSimpleSalePilot(
          _validContext(saleItems: [item], stockItems: [item]),
        );
        expect(
          result.rejectionCode,
          PdvV1SimpleSalePilotRejectionCode.quantidadeInvalid,
        );
      }
    });

    test('26. operationId/saleId inválidos ou divergentes rejeitam', () {
      expect(
        pdvV1MapSimpleSalePilot(_validContext(operationId: '')).rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.operationIdentityInvalid,
      );
      expect(
        pdvV1MapSimpleSalePilot(_validContext(saleId: '')).rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.operationIdentityInvalid,
      );
      expect(
        pdvV1MapSimpleSalePilot(
          _validContext(operationId: 'op-a', saleId: 'op-b'),
        ).rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.operationIdentityInvalid,
      );
      expect(
        pdvV1MapSimpleSalePilot(
          _validContext(operationId: ' op-001'),
        ).rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.operationIdentityInvalid,
      );
    });

    test('27. lojaId vazio ou com espaço externo rejeita', () {
      expect(
        pdvV1MapSimpleSalePilot(_validContext(lojaId: '')).rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.lojaIdInvalid,
      );
      expect(
        pdvV1MapSimpleSalePilot(_validContext(lojaId: ' loja-a')).rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.lojaIdInvalid,
      );
    });

    test('28. preparedAtEpochMs inválido rejeita via preparador', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(preparedAtEpochMs: 0),
      );
      expect(result.kind, PdvV1SimpleSalePilotSelectionKind.remainsLegacy);
      expect(
        result.rejectionCode,
        PdvV1SimpleSalePilotRejectionCode.preparationRejected,
      );
      expect(
        result.preparationRejectionCode,
        PdvV1SimpleSalePreparationRejectionCode.preparedAtInvalid,
      );
      expect(result.preparation, isNull);
    });

    test('29. mesmo contexto válido três vezes produz hashes iguais', () {
      final context = _validContext();
      final r1 = pdvV1MapSimpleSalePilot(context);
      final r2 = pdvV1MapSimpleSalePilot(context);
      final r3 = pdvV1MapSimpleSalePilot(context);

      expect(r1.preparation!.snapshotHash, r2.preparation!.snapshotHash);
      expect(r2.preparation!.snapshotHash, r3.preparation!.snapshotHash);
      expect(r1.preparation!.txItemsHash, r2.preparation!.txItemsHash);
    });

    test('30. remainsLegacy retorna preparation nulo', () {
      final result = pdvV1MapSimpleSalePilot(
        _validContext(origin: PdvV1SimpleSalePilotOrigin.catalogo),
      );
      expect(result.preparation, isNull);
    });

    test('31. selectedForV1 não expõe writer/journal/remoto', () {
      final result = pdvV1MapSimpleSalePilot(_validContext());
      expect(result.kind, PdvV1SimpleSalePilotSelectionKind.selectedForV1);
      expect(result.preparation, isNotNull);
      expect(result.preparation!.preparedSnapshot, isNotEmpty);
    });
  });

  group('pdvV1IsKnownSimpleDirectStock', () {
    test('produto simples válido retorna true', () {
      expect(pdvV1IsKnownSimpleDirectStock(_simpleProduct()), isTrue);
    });

    test('produto combo retorna false', () {
      expect(
        pdvV1IsKnownSimpleDirectStock(_simpleProduct(tipoProduto: 'combo')),
        isFalse,
      );
    });
  });
}
