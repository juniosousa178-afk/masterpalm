import 'pdv_v1_internal_errors.dart';

/// Valida e congela árvore JSON (null, bool, num, String, List, Map).
dynamic _pdvV1DeepFreezeJson(dynamic value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(
      value.map(_pdvV1DeepFreezeJson).toList(growable: false),
    );
  }
  if (value is Map) {
    final frozen = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw PdvV1ValidationError('chave preparedSnapshot não é String.');
      }
      frozen[entry.key as String] = _pdvV1DeepFreezeJson(entry.value);
    }
    return Map<String, dynamic>.unmodifiable(frozen);
  }
  throw PdvV1ValidationError(
    'tipo não compatível com JSON: ${value.runtimeType}',
  );
}

/// Cópia defensiva profunda mutável (para serialização externa).
dynamic _pdvV1DeepCopyJson(dynamic value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is List) {
    return value.map(_pdvV1DeepCopyJson).toList(growable: true);
  }
  if (value is Map) {
    final copy = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw PdvV1ValidationError('chave preparedSnapshot não é String.');
      }
      copy[entry.key as String] = _pdvV1DeepCopyJson(entry.value);
    }
    return copy;
  }
  throw PdvV1ValidationError(
    'tipo não compatível com JSON: ${value.runtimeType}',
  );
}

Map<String, dynamic> _pdvV1DeepCopyJsonMap(Map<String, dynamic> source) {
  final copied = _pdvV1DeepCopyJson(source);
  if (copied is! Map<String, dynamic>) {
    throw PdvV1ValidationError('preparedSnapshot não é mapa.');
  }
  return copied;
}

/// Congela árvore JSON para evidência de journal malformado.
dynamic pdvV1FreezeJsonTree(dynamic value) => _pdvV1DeepFreezeJson(value);

const pdvV1ProtocolVersion = 1;

/// Origem do fluxo — somente [novaVendaPdvFuture] é suportada na fundação 7A-A.
enum PdvV1InternalOrigin {
  novaVendaPdvFuture,
  orderReviewLegacy,
  pedidoPublicoLegacy,
  catalogoLegacy,
  editarVendaLegacy,
  cancelamentoLegacy,
}

/// Valor de protocolo persistido para origem PDV nova venda.
const pdvV1OrigemProtocolValue = 'pdv';

String pdvV1InternalOriginToProtocol(PdvV1InternalOrigin origin) {
  switch (origin) {
    case PdvV1InternalOrigin.novaVendaPdvFuture:
      return pdvV1OrigemProtocolValue;
    default:
      return origin.name;
  }
}

PdvV1InternalOrigin? pdvV1InternalOriginFromProtocol(String value) {
  final v = value.trim();
  if (v == pdvV1OrigemProtocolValue) {
    return PdvV1InternalOrigin.novaVendaPdvFuture;
  }
  for (final o in PdvV1InternalOrigin.values) {
    if (o.name == v) return o;
  }
  return null;
}

/// Snapshot imutável preparado antes de qualquer integração externa.
class PdvV1PreparedSnapshot {
  PdvV1PreparedSnapshot({
    required this.protocolVersion,
    required this.operationId,
    required this.saleId,
    required this.lojaId,
    required this.origem,
    required this.preparedAtEpochMs,
    required Map<String, dynamic> preparedSnapshot,
    required this.snapshotHash,
    required this.txItemsHash,
    required this.isFiado,
    required this.hasCombo,
    required this.isEdicao,
    required this.isCancelamento,
  }) : _preparedSnapshot =
            _pdvV1DeepFreezeJson(preparedSnapshot) as Map<String, dynamic>;

  final int protocolVersion;
  final String operationId;
  final String saleId;
  final String lojaId;
  final PdvV1InternalOrigin origem;
  final int preparedAtEpochMs;
  final Map<String, dynamic> _preparedSnapshot;
  final String snapshotHash;
  final String txItemsHash;
  final bool isFiado;
  final bool hasCombo;
  final bool isEdicao;
  final bool isCancelamento;

  /// Vista somente leitura — mapa/listas internas congelados.
  Map<String, dynamic> get preparedSnapshot => _preparedSnapshot;

  String get origemProtocol => pdvV1InternalOriginToProtocol(origem);

  Map<String, dynamic> toJson() => {
        'protocolVersion': protocolVersion,
        'operationId': operationId,
        'saleId': saleId,
        'lojaId': lojaId,
        'origem': origemProtocol,
        'preparedAtEpochMs': preparedAtEpochMs,
        'preparedSnapshot': _pdvV1DeepCopyJsonMap(_preparedSnapshot),
        'snapshotHash': snapshotHash,
        'txItemsHash': txItemsHash,
        'isFiado': isFiado,
        'hasCombo': hasCombo,
        'isEdicao': isEdicao,
        'isCancelamento': isCancelamento,
      };

  static PdvV1PreparedSnapshot fromJson(Map<String, dynamic> json) {
    final snapRaw = json['preparedSnapshot'];
    if (snapRaw is! Map) {
      throw PdvV1ValidationError('preparedSnapshot inválido ou ausente.');
    }
    final origemStr = (json['origem'] ?? '').toString();
    final origem = pdvV1InternalOriginFromProtocol(origemStr);
    if (origem == null) {
      throw PdvV1ValidationError('origem inválida: $origemStr');
    }
    return PdvV1PreparedSnapshot(
      protocolVersion: _asInt(json['protocolVersion']),
      operationId: (json['operationId'] ?? '').toString(),
      saleId: (json['saleId'] ?? '').toString(),
      lojaId: (json['lojaId'] ?? '').toString(),
      origem: origem,
      preparedAtEpochMs: _asInt(json['preparedAtEpochMs']),
      preparedSnapshot: Map<String, dynamic>.from(snapRaw),
      snapshotHash: (json['snapshotHash'] ?? '').toString(),
      txItemsHash: (json['txItemsHash'] ?? '').toString(),
      isFiado: json['isFiado'] == true,
      hasCombo: json['hasCombo'] == true,
      isEdicao: json['isEdicao'] == true,
      isCancelamento: json['isCancelamento'] == true,
    );
  }

  /// Validação fail-closed para escopo 7A-A executável.
  void validateForFoundation7AA() {
    if (protocolVersion != pdvV1ProtocolVersion) {
      throw PdvV1ValidationError(
        'protocolVersion deve ser $pdvV1ProtocolVersion.',
      );
    }
    if (operationId.trim().isEmpty) {
      throw PdvV1ValidationError('operationId vazio.');
    }
    if (saleId.trim().isEmpty) {
      throw PdvV1ValidationError('saleId vazio.');
    }
    if (lojaId.trim().isEmpty) {
      throw PdvV1ValidationError('lojaId vazio.');
    }
    if (snapshotHash.trim().isEmpty) {
      throw PdvV1ValidationError('snapshotHash vazio.');
    }
    if (txItemsHash.trim().isEmpty) {
      throw PdvV1ValidationError('txItemsHash vazio.');
    }
    if (preparedSnapshot.isEmpty) {
      throw PdvV1ValidationError('preparedSnapshot vazio.');
    }
    if (preparedAtEpochMs <= 0) {
      throw PdvV1ValidationError('preparedAtEpochMs inválido.');
    }
    if (origem != PdvV1InternalOrigin.novaVendaPdvFuture) {
      throw PdvV1ScopeNotSupportedError(
        'Origem ${origem.name} não suportada na fundação 7A-A.',
      );
    }
    if (isFiado) {
      throw PdvV1ScopeNotSupportedError(
          'Fiado não suportado na fundação 7A-A.');
    }
    if (hasCombo) {
      throw PdvV1ScopeNotSupportedError(
          'Combo não suportado na fundação 7A-A.');
    }
    if (isEdicao) {
      throw PdvV1ScopeNotSupportedError(
          'Edição não suportada na fundação 7A-A.');
    }
    if (isCancelamento) {
      throw PdvV1ScopeNotSupportedError(
        'Cancelamento não suportado na fundação 7A-A.',
      );
    }
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

/// Representação serializável de marcador remoto para o planner puro.
class PdvV1RemoteMarkerInput {
  const PdvV1RemoteMarkerInput({
    required this.presente,
    this.protocolVersion = 0,
    this.origem = '',
    this.lojaId = '',
    this.operationId = '',
    this.saleId = '',
    this.baixaAplicada = false,
    this.estornoAplicado = false,
    this.txItemsHash = '',
  });

  const PdvV1RemoteMarkerInput.ausente()
      : presente = false,
        protocolVersion = 0,
        origem = '',
        lojaId = '',
        operationId = '',
        saleId = '',
        baixaAplicada = false,
        estornoAplicado = false,
        txItemsHash = '';

  final bool presente;
  final int protocolVersion;
  final String origem;
  final String lojaId;
  final String operationId;
  final String saleId;
  final bool baixaAplicada;
  final bool estornoAplicado;
  final String txItemsHash;

  bool get validoV1 =>
      presente &&
      protocolVersion == pdvV1ProtocolVersion &&
      origem == pdvV1OrigemProtocolValue;

  Map<String, dynamic> toJson() => {
        'presente': presente,
        'protocolVersion': protocolVersion,
        'origem': origem,
        'lojaId': lojaId,
        'operationId': operationId,
        'saleId': saleId,
        'baixaAplicada': baixaAplicada,
        'estornoAplicado': estornoAplicado,
        'txItemsHash': txItemsHash,
      };

  static PdvV1RemoteMarkerInput fromJson(Map<String, dynamic> json) {
    return PdvV1RemoteMarkerInput(
      presente: json['presente'] == true,
      protocolVersion: _asInt(json['protocolVersion']),
      origem: (json['origem'] ?? '').toString(),
      lojaId: (json['lojaId'] ?? '').toString(),
      operationId: (json['operationId'] ?? '').toString(),
      saleId: (json['saleId'] ?? '').toString(),
      baixaAplicada: json['baixaAplicada'] == true,
      estornoAplicado: json['estornoAplicado'] == true,
      txItemsHash: (json['txItemsHash'] ?? '').toString(),
    );
  }
}

/// Item congelado de txItems para o planner.
class PdvV1TxItemFrozen {
  const PdvV1TxItemFrozen({
    required this.productId,
    required this.quantidade,
  });

  final String productId;
  final int quantidade;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'quantidade': quantidade,
      };

  static PdvV1TxItemFrozen fromJson(Map<String, dynamic> json) {
    return PdvV1TxItemFrozen(
      productId: (json['productId'] ?? '').toString(),
      quantidade: _asInt(json['quantidade']),
    );
  }
}

/// Entrada mínima para política Hive upsert.
class PdvV1HiveSaleMatch {
  const PdvV1HiveSaleMatch({
    required this.hiveKey,
    required this.saleId,
    required this.snapshotHash,
  });

  /// Chave Hive — `null` é inválido; `0` é válido (primeiro `Box.add`).
  final int? hiveKey;
  final String saleId;
  final String snapshotHash;

  Map<String, dynamic> toJson() => {
        if (hiveKey != null) 'hiveKey': hiveKey,
        'saleId': saleId,
        'snapshotHash': snapshotHash,
      };

  static PdvV1HiveSaleMatch fromJson(Map<String, dynamic> json) {
    final rawKey = json['hiveKey'];
    int? hiveKey;
    if (rawKey == null) {
      hiveKey = null;
    } else if (rawKey is int) {
      hiveKey = rawKey;
    } else {
      hiveKey = int.tryParse('$rawKey');
    }
    return PdvV1HiveSaleMatch(
      hiveKey: hiveKey,
      saleId: (json['saleId'] ?? '').toString(),
      snapshotHash: (json['snapshotHash'] ?? '').toString(),
    );
  }
}
