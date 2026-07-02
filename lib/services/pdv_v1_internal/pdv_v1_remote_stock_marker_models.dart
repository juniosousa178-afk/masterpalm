import 'pdv_v1_internal_errors.dart';
import 'pdv_v1_internal_models.dart';

/// Coleção remota de saldo — evidência: [EstoqueTransactionService], [FSPaths.estoqueProdutosCol].
const pdvV1RemoteStockCollectionSegment = 'estoque_produtos';

/// Campo numérico de saldo simples — evidência: `data['quantidade']` em baixa transacional.
const pdvV1RemoteStockQuantityField = 'quantidade';

/// Coleção de markers de baixa — evidência: Rules R1 `estoque_baixa_pagamento/{markerId}`.
const pdvV1RemoteMarkerCollectionSegment = 'estoque_baixa_pagamento';

/// Chaves fechadas do marker V1 remoto (Rules R1).
const pdvV1RemoteMarkerV1Keys = [
  'protocolVersion',
  'origem',
  'operationId',
  'saleId',
  'lojaId',
  'baixaAplicada',
  'snapshotHash',
  'txItemsHash',
];

/// Outcome tipado da aplicação atômica R2-A.
enum PdvV1RemoteStockMarkerApplyOutcome {
  applied,
  alreadyApplied,
  remoteMarkerIdentityConflict,
  stockDocumentInvalid,
  insufficientStock,
  remoteTransactionUnavailable,
}

/// Resultado fechado de [PdvV1RemoteStockMarkerExecutor.applyOnce].
class PdvV1RemoteStockMarkerApplyResult {
  const PdvV1RemoteStockMarkerApplyResult({required this.outcome});

  final PdvV1RemoteStockMarkerApplyOutcome outcome;

  bool get isApplied => outcome == PdvV1RemoteStockMarkerApplyOutcome.applied;

  bool get isAlreadyApplied =>
      outcome == PdvV1RemoteStockMarkerApplyOutcome.alreadyApplied;
}

/// Plano V1 fechado para débito simples de um documento de estoque + marker.
class PdvV1RemoteStockMarkerPlan {
  PdvV1RemoteStockMarkerPlan({
    required this.operationId,
    required this.saleId,
    required this.lojaId,
    required this.origem,
    required this.protocolVersion,
    required this.snapshotHash,
    required this.txItemsHash,
    required this.stockDocumentId,
    required this.quantityToDebit,
  }) : stockQuantityField = pdvV1RemoteStockQuantityField {
    _validate();
  }

  final String operationId;
  final String saleId;
  final String lojaId;
  final String origem;
  final int protocolVersion;
  final String snapshotHash;
  final String txItemsHash;
  final String stockDocumentId;
  final int quantityToDebit;

  /// Constante interna — não aceita campo livre de call site.
  final String stockQuantityField;

  void _validate() {
    if (operationId.trim().isEmpty) {
      throw PdvV1ValidationError('operationId vazio.');
    }
    if (saleId.trim().isEmpty) {
      throw PdvV1ValidationError('saleId vazio.');
    }
    if (lojaId.trim().isEmpty) {
      throw PdvV1ValidationError('lojaId vazio.');
    }
    if (origem != pdvV1OrigemProtocolValue) {
      throw PdvV1ValidationError('origem deve ser pdv.');
    }
    if (protocolVersion != pdvV1ProtocolVersion) {
      throw PdvV1ValidationError('protocolVersion deve ser 1.');
    }
    if (snapshotHash.trim().isEmpty) {
      throw PdvV1ValidationError('snapshotHash vazio.');
    }
    if (txItemsHash.trim().isEmpty) {
      throw PdvV1ValidationError('txItemsHash vazio.');
    }
    if (stockDocumentId.trim().isEmpty) {
      throw PdvV1ValidationError('stockDocumentId vazio.');
    }
    if (quantityToDebit <= 0) {
      throw PdvV1ValidationError('quantityToDebit deve ser int positivo.');
    }
    if (stockQuantityField != pdvV1RemoteStockQuantityField) {
      throw PdvV1ValidationError('stockQuantityField inválido.');
    }
  }

  /// Marker remoto V1 com exatamente 8 chaves, ordem determinística na serialização.
  Map<String, dynamic> toRemoteMarkerMap() {
    return {
      'protocolVersion': protocolVersion,
      'origem': origem,
      'operationId': operationId,
      'saleId': saleId,
      'lojaId': lojaId,
      'baixaAplicada': true,
      'snapshotHash': snapshotHash,
      'txItemsHash': txItemsHash,
    };
  }

  /// Serialização determinística para comparação estrutural.
  Map<String, dynamic> toDeterministicJson() {
    final marker = toRemoteMarkerMap();
    final keys = marker.keys.toList()..sort();
    final sortedMarker = <String, dynamic>{for (final k in keys) k: marker[k]};
    return {
      'operationId': operationId,
      'saleId': saleId,
      'lojaId': lojaId,
      'origem': origem,
      'protocolVersion': protocolVersion,
      'snapshotHash': snapshotHash,
      'txItemsHash': txItemsHash,
      'stockDocumentId': stockDocumentId,
      'stockQuantityField': stockQuantityField,
      'quantityToDebit': quantityToDebit,
      'remoteMarker': sortedMarker,
    };
  }

  /// Avalia compatibilidade estrutural de marker existente com este plan.
  PdvV1RemoteMarkerCompatibility evaluateExistingMarker(
    Map<String, dynamic>? raw,
  ) {
    if (raw == null) {
      return PdvV1RemoteMarkerCompatibility.absent;
    }
    final keys = raw.keys.toSet();
    final expectedKeys = pdvV1RemoteMarkerV1Keys.toSet();
    if (!keys.containsAll(expectedKeys) || keys.length != expectedKeys.length) {
      return PdvV1RemoteMarkerCompatibility.incompatible;
    }
    if (raw['protocolVersion'] is! int || raw['protocolVersion'] != 1) {
      return PdvV1RemoteMarkerCompatibility.incompatible;
    }
    if (raw['origem'] != pdvV1OrigemProtocolValue) {
      return PdvV1RemoteMarkerCompatibility.incompatible;
    }
    if (raw['baixaAplicada'] != true) {
      return PdvV1RemoteMarkerCompatibility.incompatible;
    }
    final expected = toRemoteMarkerMap();
    for (final key in pdvV1RemoteMarkerV1Keys) {
      if (raw[key] != expected[key]) {
        return PdvV1RemoteMarkerCompatibility.incompatible;
      }
    }
    return PdvV1RemoteMarkerCompatibility.compatible;
  }
}

enum PdvV1RemoteMarkerCompatibility {
  absent,
  compatible,
  incompatible,
}

/// Valida saldo simples no documento de estoque (somente campo [quantidade]).
PdvV1RemoteStockQuantityValidation validateStockQuantityField({
  required Map<String, dynamic>? stockDocument,
  required String quantityField,
  required int quantityToDebit,
}) {
  if (stockDocument == null) {
    return PdvV1RemoteStockQuantityValidation.documentAbsent;
  }
  if (!stockDocument.containsKey(quantityField)) {
    return PdvV1RemoteStockQuantityValidation.fieldAbsent;
  }
  final raw = stockDocument[quantityField];
  if (raw is! int) {
    return PdvV1RemoteStockQuantityValidation.fieldNotInt;
  }
  if (raw < 0) {
    return PdvV1RemoteStockQuantityValidation.fieldNegative;
  }
  if (raw < quantityToDebit) {
    return PdvV1RemoteStockQuantityValidation.insufficient;
  }
  return PdvV1RemoteStockQuantityValidation.valid;
}

enum PdvV1RemoteStockQuantityValidation {
  valid,
  documentAbsent,
  fieldAbsent,
  fieldNotInt,
  fieldNegative,
  insufficient,
}
