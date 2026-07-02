import 'pdv_v1_canonical_json.dart';
import 'pdv_v1_internal_models.dart';

/// Códigos fechados de rejeição fail-closed para preparação de venda simples.
enum PdvV1SimpleSalePreparationRejectionCode {
  operationIdInvalid,
  saleIdInvalid,
  operationAndSaleIdMismatch,
  lojaIdInvalid,
  preparedAtInvalid,
  saleLineCountNotOne,
  stockLineCountNotOne,
  stockDocumentIdInvalid,
  quantidadeNotPositive,
  notNewPdvSale,
  comboNotSupported,
  fiadoNotSupported,
  edicaoNotSupported,
  cancelamentoNotSupported,
  variationSelectionNotSupported,
  productVariationNotSupported,
  stockShapeNotKnownSimpleDirect,
}

/// Entrada pura e imutável para preparação de venda simples PDV V1.
class PdvV1SimpleSalePreparationInput {
  const PdvV1SimpleSalePreparationInput({
    required this.operationId,
    required this.saleId,
    required this.lojaId,
    required this.preparedAtEpochMs,
    required this.stockDocumentId,
    required this.quantidade,
    required this.saleLineCount,
    required this.stockLineCount,
    required this.isNewPdvSale,
    required this.hasCombo,
    required this.isFiado,
    required this.isEdicao,
    required this.isCancelamento,
    required this.hasVariationSelection,
    required this.productHasVariationDefinition,
    required this.stockShapeIsKnownSimpleDirect,
  });

  final String operationId;
  final String saleId;
  final String lojaId;
  final int preparedAtEpochMs;
  final String stockDocumentId;
  final int quantidade;
  final int saleLineCount;
  final int stockLineCount;
  final bool isNewPdvSale;
  final bool hasCombo;
  final bool isFiado;
  final bool isEdicao;
  final bool isCancelamento;
  final bool hasVariationSelection;
  final bool productHasVariationDefinition;
  final bool stockShapeIsKnownSimpleDirect;
}

/// Resultado fechado da preparação — elegível ou rejeitado.
class PdvV1SimpleSalePreparationResult {
  const PdvV1SimpleSalePreparationResult._({
    required this.isEligible,
    this.rejectionCode,
    this.prepared,
  });

  final bool isEligible;
  final PdvV1SimpleSalePreparationRejectionCode? rejectionCode;
  final PdvV1PreparedSnapshot? prepared;

  factory PdvV1SimpleSalePreparationResult.eligible(
    PdvV1PreparedSnapshot prepared,
  ) =>
      PdvV1SimpleSalePreparationResult._(
        isEligible: true,
        prepared: prepared,
      );

  factory PdvV1SimpleSalePreparationResult.rejected(
    PdvV1SimpleSalePreparationRejectionCode code,
  ) =>
      PdvV1SimpleSalePreparationResult._(
        isEligible: false,
        rejectionCode: code,
      );
}

/// Prepara [input] em snapshot V1 puro — sem journal, remoto ou persistência.
PdvV1SimpleSalePreparationResult pdvV1PrepareSimpleSale(
  PdvV1SimpleSalePreparationInput input,
) {
  PdvV1SimpleSalePreparationResult reject(
    PdvV1SimpleSalePreparationRejectionCode code,
  ) =>
      PdvV1SimpleSalePreparationResult.rejected(code);

  if (!_isExactNonEmptyId(input.operationId)) {
    return reject(PdvV1SimpleSalePreparationRejectionCode.operationIdInvalid);
  }
  if (!_isExactNonEmptyId(input.saleId)) {
    return reject(PdvV1SimpleSalePreparationRejectionCode.saleIdInvalid);
  }
  if (input.operationId != input.saleId) {
    return reject(
      PdvV1SimpleSalePreparationRejectionCode.operationAndSaleIdMismatch,
    );
  }
  if (!_isExactNonEmptyId(input.lojaId)) {
    return reject(PdvV1SimpleSalePreparationRejectionCode.lojaIdInvalid);
  }
  if (input.preparedAtEpochMs <= 0) {
    return reject(PdvV1SimpleSalePreparationRejectionCode.preparedAtInvalid);
  }
  if (input.saleLineCount != 1) {
    return reject(PdvV1SimpleSalePreparationRejectionCode.saleLineCountNotOne);
  }
  if (input.stockLineCount != 1) {
    return reject(PdvV1SimpleSalePreparationRejectionCode.stockLineCountNotOne);
  }
  if (!_isExactNonEmptyId(input.stockDocumentId)) {
    return reject(
      PdvV1SimpleSalePreparationRejectionCode.stockDocumentIdInvalid,
    );
  }
  if (input.quantidade <= 0) {
    return reject(
      PdvV1SimpleSalePreparationRejectionCode.quantidadeNotPositive,
    );
  }
  if (!input.isNewPdvSale) {
    return reject(PdvV1SimpleSalePreparationRejectionCode.notNewPdvSale);
  }
  if (input.hasCombo) {
    return reject(PdvV1SimpleSalePreparationRejectionCode.comboNotSupported);
  }
  if (input.isFiado) {
    return reject(PdvV1SimpleSalePreparationRejectionCode.fiadoNotSupported);
  }
  if (input.isEdicao) {
    return reject(PdvV1SimpleSalePreparationRejectionCode.edicaoNotSupported);
  }
  if (input.isCancelamento) {
    return reject(
      PdvV1SimpleSalePreparationRejectionCode.cancelamentoNotSupported,
    );
  }
  if (input.hasVariationSelection) {
    return reject(
      PdvV1SimpleSalePreparationRejectionCode.variationSelectionNotSupported,
    );
  }
  if (input.productHasVariationDefinition) {
    return reject(
      PdvV1SimpleSalePreparationRejectionCode.productVariationNotSupported,
    );
  }
  if (!input.stockShapeIsKnownSimpleDirect) {
    return reject(
      PdvV1SimpleSalePreparationRejectionCode.stockShapeNotKnownSimpleDirect,
    );
  }

  final txItems = <Map<String, Object>>[
    <String, Object>{
      'productId': input.stockDocumentId,
      'quantidade': input.quantidade,
    },
  ];

  final txItemsHash = pdvV1CanonicalSha256(txItems);

  final payloadSemSnapshotHash = <String, Object>{
    'protocolVersion': pdvV1ProtocolVersion,
    'operationId': input.operationId,
    'saleId': input.saleId,
    'lojaId': input.lojaId,
    'origem': pdvV1OrigemProtocolValue,
    'txItemsHash': txItemsHash,
    'txItems': txItems,
  };

  final snapshotHash = pdvV1CanonicalSha256(payloadSemSnapshotHash);

  final innerPreparedSnapshot = <String, dynamic>{
    'protocolVersion': pdvV1ProtocolVersion,
    'operationId': input.operationId,
    'saleId': input.saleId,
    'lojaId': input.lojaId,
    'origem': pdvV1OrigemProtocolValue,
    'snapshotHash': snapshotHash,
    'txItemsHash': txItemsHash,
    'txItems': txItems,
  };

  final prepared = PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: input.operationId,
    saleId: input.saleId,
    lojaId: input.lojaId,
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: input.preparedAtEpochMs,
    preparedSnapshot: innerPreparedSnapshot,
    snapshotHash: snapshotHash,
    txItemsHash: txItemsHash,
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );

  prepared.validateForFoundation7AA();

  return PdvV1SimpleSalePreparationResult.eligible(prepared);
}

bool _isExactNonEmptyId(String value) =>
    value.isNotEmpty && value == value.trim();
