import '../../models/produto.dart';
import '../../models/venda_item.dart';
import 'pdv_v1_internal_models.dart';
import 'pdv_v1_simple_sale_preparation.dart';

/// Origem tipada fechada para tentativa futura de piloto PDV V1.
enum PdvV1SimpleSalePilotOrigin {
  novaVendaModal,
  pedidoPublico,
  orderReview,
  catalogo,
  posPagamento,
  webhookPagamento,
  unknown,
}

/// Contexto imutável e tipado para mapeamento de elegibilidade do piloto.
class PdvV1SimpleSalePilotContext {
  const PdvV1SimpleSalePilotContext({
    required this.origin,
    required this.operationId,
    required this.saleId,
    required this.lojaId,
    required this.preparedAtEpochMs,
    required this.saleItems,
    required this.stockItems,
    required this.resolvedProduct,
    required this.isFiado,
    required this.hasComboSelection,
    required this.isEdicao,
    required this.isCancelamento,
  });

  final PdvV1SimpleSalePilotOrigin origin;
  final String operationId;
  final String saleId;
  final String lojaId;
  final int preparedAtEpochMs;
  final List<VendaItem> saleItems;
  final List<VendaItem> stockItems;
  final Produto resolvedProduct;
  final bool isFiado;
  final bool hasComboSelection;
  final bool isEdicao;
  final bool isCancelamento;
}

/// Resultado fechado da seleção de ramo piloto versus legado.
enum PdvV1SimpleSalePilotSelectionKind { selectedForV1, remainsLegacy }

/// Códigos fechados de rejeição fail-closed antes de journal ou baixa.
enum PdvV1SimpleSalePilotRejectionCode {
  unsupportedOrigin,
  notNewPdvSale,
  fiadoNotSupported,
  comboNotSupported,
  edicaoNotSupported,
  cancelamentoNotSupported,
  saleLineCountNotOne,
  stockLineCountNotOne,
  variationSelectionNotSupported,
  productVariationNotSupported,
  stockShapeNotKnownSimpleDirect,
  stockDocumentIdInvalid,
  quantidadeInvalid,
  operationIdentityInvalid,
  lojaIdInvalid,
  preparationRejected,
}

/// Seleção imutável — elegível para V1 ou permanece no legado com motivo fechado.
class PdvV1SimpleSalePilotSelection {
  const PdvV1SimpleSalePilotSelection({
    required this.kind,
    this.rejectionCode,
    this.preparation,
    this.preparationRejectionCode,
  });

  final PdvV1SimpleSalePilotSelectionKind kind;
  final PdvV1SimpleSalePilotRejectionCode? rejectionCode;
  final PdvV1PreparedSnapshot? preparation;
  final PdvV1SimpleSalePreparationRejectionCode? preparationRejectionCode;
}

/// Fail-closed: produto com estoque escalar simples conhecido, sem combo/variação/grade.
bool pdvV1IsKnownSimpleDirectStock(Produto product) {
  if (product.ehCombo) return false;
  if (product.usaVariacoes) return false;
  if (product.variacoes != null && product.variacoes!.isNotEmpty) return false;
  if (product.estoquePorTamanho.isNotEmpty) return false;
  if (product.temEstoquePorTamanhoComTamanhoReal) return false;
  if (product.temVariacaoSoloTamanho) return false;
  if (product.temVariacaoSoloCor) return false;
  if (product.temVariacaoTamanhoECor) return false;
  if (product.exigeSelecaoTamanhoNaVenda) return false;
  if (product.itensCombo != null && product.itensCombo!.isNotEmpty) {
    return false;
  }
  return true;
}

PdvV1SimpleSalePilotSelection _remainsLegacy(
  PdvV1SimpleSalePilotRejectionCode code,
) =>
    PdvV1SimpleSalePilotSelection(
      kind: PdvV1SimpleSalePilotSelectionKind.remainsLegacy,
      rejectionCode: code,
    );

bool _isExactNonEmptyId(String value) =>
    value.isNotEmpty && value == value.trim();

bool _hasConcreteVariationSelection(VendaItem item) =>
    item.tamanho.isNotEmpty ||
    item.cor.isNotEmpty ||
    item.extraValor.isNotEmpty;

PdvV1SimpleSalePilotRejectionCode? _productShapeRejectionCode(Produto product) {
  if (product.usaVariacoes) {
    return PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported;
  }
  if (product.variacoes != null && product.variacoes!.isNotEmpty) {
    return PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported;
  }
  if (product.estoquePorTamanho.isNotEmpty) {
    return PdvV1SimpleSalePilotRejectionCode.stockShapeNotKnownSimpleDirect;
  }
  if (product.temEstoquePorTamanhoComTamanhoReal) {
    return PdvV1SimpleSalePilotRejectionCode.stockShapeNotKnownSimpleDirect;
  }
  if (product.temVariacaoSoloTamanho) {
    return PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported;
  }
  if (product.temVariacaoSoloCor) {
    return PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported;
  }
  if (product.temVariacaoTamanhoECor) {
    return PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported;
  }
  if (product.exigeSelecaoTamanhoNaVenda) {
    return PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported;
  }
  if (product.itensCombo != null && product.itensCombo!.isNotEmpty) {
    return PdvV1SimpleSalePilotRejectionCode.productVariationNotSupported;
  }
  return null;
}

/// Pré-branch puro: decide se tentativa futura pode selecionar piloto PDV V1.
///
/// [remainsLegacy] significa que a tentativa nunca entrou no ramo V1 e deve
/// continuar no legado futuro, antes de qualquer journal ou baixa — não é
/// fallback pós-erro V1.
PdvV1SimpleSalePilotSelection pdvV1MapSimpleSalePilot(
  PdvV1SimpleSalePilotContext context,
) {
  if (context.origin != PdvV1SimpleSalePilotOrigin.novaVendaModal) {
    return _remainsLegacy(PdvV1SimpleSalePilotRejectionCode.unsupportedOrigin);
  }

  if (context.isEdicao) {
    return _remainsLegacy(PdvV1SimpleSalePilotRejectionCode.edicaoNotSupported);
  }
  if (context.isCancelamento) {
    return _remainsLegacy(
      PdvV1SimpleSalePilotRejectionCode.cancelamentoNotSupported,
    );
  }
  if (context.isFiado) {
    return _remainsLegacy(PdvV1SimpleSalePilotRejectionCode.fiadoNotSupported);
  }
  if (context.hasComboSelection) {
    return _remainsLegacy(PdvV1SimpleSalePilotRejectionCode.comboNotSupported);
  }
  if (context.resolvedProduct.ehCombo) {
    return _remainsLegacy(PdvV1SimpleSalePilotRejectionCode.comboNotSupported);
  }

  if (context.saleItems.length != 1) {
    return _remainsLegacy(
      PdvV1SimpleSalePilotRejectionCode.saleLineCountNotOne,
    );
  }
  if (context.stockItems.length != 1) {
    return _remainsLegacy(
      PdvV1SimpleSalePilotRejectionCode.stockLineCountNotOne,
    );
  }

  final saleItem = context.saleItems.single;
  if (_hasConcreteVariationSelection(saleItem)) {
    return _remainsLegacy(
      PdvV1SimpleSalePilotRejectionCode.variationSelectionNotSupported,
    );
  }

  if (!pdvV1IsKnownSimpleDirectStock(context.resolvedProduct)) {
    final shapeCode = _productShapeRejectionCode(context.resolvedProduct);
    return _remainsLegacy(
      shapeCode ??
          PdvV1SimpleSalePilotRejectionCode.stockShapeNotKnownSimpleDirect,
    );
  }

  final stockDocumentId = context.resolvedProduct.idFirebase;
  if (!_isExactNonEmptyId(stockDocumentId)) {
    return _remainsLegacy(
      PdvV1SimpleSalePilotRejectionCode.stockDocumentIdInvalid,
    );
  }

  final quantidade = context.stockItems.single.quantidade;
  if (quantidade <= 0) {
    return _remainsLegacy(PdvV1SimpleSalePilotRejectionCode.quantidadeInvalid);
  }

  if (!_isExactNonEmptyId(context.operationId) ||
      !_isExactNonEmptyId(context.saleId) ||
      context.operationId != context.saleId) {
    return _remainsLegacy(
      PdvV1SimpleSalePilotRejectionCode.operationIdentityInvalid,
    );
  }
  if (!_isExactNonEmptyId(context.lojaId)) {
    return _remainsLegacy(PdvV1SimpleSalePilotRejectionCode.lojaIdInvalid);
  }

  final preparationResult = pdvV1PrepareSimpleSale(
    PdvV1SimpleSalePreparationInput(
      operationId: context.operationId,
      saleId: context.saleId,
      lojaId: context.lojaId,
      preparedAtEpochMs: context.preparedAtEpochMs,
      stockDocumentId: stockDocumentId,
      quantidade: quantidade,
      saleLineCount: context.saleItems.length,
      stockLineCount: context.stockItems.length,
      isNewPdvSale: true,
      hasCombo: false,
      isFiado: false,
      isEdicao: false,
      isCancelamento: false,
      hasVariationSelection: false,
      productHasVariationDefinition: false,
      stockShapeIsKnownSimpleDirect: true,
    ),
  );

  if (!preparationResult.isEligible) {
    return PdvV1SimpleSalePilotSelection(
      kind: PdvV1SimpleSalePilotSelectionKind.remainsLegacy,
      rejectionCode: PdvV1SimpleSalePilotRejectionCode.preparationRejected,
      preparationRejectionCode: preparationResult.rejectionCode,
    );
  }

  return PdvV1SimpleSalePilotSelection(
    kind: PdvV1SimpleSalePilotSelectionKind.selectedForV1,
    preparation: preparationResult.prepared,
  );
}
