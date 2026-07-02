import 'pdv_v1_internal_models.dart';
import 'pdv_v1_remote_stock_marker_models.dart';

/// Chave fechada da lista de itens em [PdvV1PreparedSnapshot.preparedSnapshot].
///
/// Evidência: [PdvV1TxItemFrozen] serializa `productId` e `quantidade`; o planner
/// V1 recebe `txItems` como lista congelada com o mesmo formato.
const pdvV1PreparedSnapshotTxItemsKey = 'txItems';

/// Campos fechados do único item simples — espelham [PdvV1TxItemFrozen.toJson].
const pdvV1PreparedSnapshotSimpleItemProductIdKey = 'productId';
const pdvV1PreparedSnapshotSimpleItemQuantidadeKey = 'quantidade';

const _pdvV1SimpleItemAllowedKeys = {
  pdvV1PreparedSnapshotSimpleItemProductIdKey,
  pdvV1PreparedSnapshotSimpleItemQuantidadeKey,
};

/// Chaves fechadas do envelope de identidade em [PdvV1PreparedSnapshot.preparedSnapshot].
const pdvV1PreparedSnapshotIdentityOperationIdKey = 'operationId';
const pdvV1PreparedSnapshotIdentitySaleIdKey = 'saleId';
const pdvV1PreparedSnapshotIdentityLojaIdKey = 'lojaId';
const pdvV1PreparedSnapshotIdentityOrigemKey = 'origem';
const pdvV1PreparedSnapshotIdentityProtocolVersionKey = 'protocolVersion';
const pdvV1PreparedSnapshotIdentitySnapshotHashKey = 'snapshotHash';
const pdvV1PreparedSnapshotIdentityTxItemsHashKey = 'txItemsHash';

const pdvV1PreparedSnapshotIdentityRequiredKeys = [
  pdvV1PreparedSnapshotIdentityOperationIdKey,
  pdvV1PreparedSnapshotIdentitySaleIdKey,
  pdvV1PreparedSnapshotIdentityLojaIdKey,
  pdvV1PreparedSnapshotIdentityOrigemKey,
  pdvV1PreparedSnapshotIdentityProtocolVersionKey,
  pdvV1PreparedSnapshotIdentitySnapshotHashKey,
  pdvV1PreparedSnapshotIdentityTxItemsHashKey,
];

/// Valida envelope de identidade interno contra o journal [PdvV1PreparedSnapshot].
bool pdvV1PreparedSnapshotIdentityEnvelopeMatchesJournal(
  PdvV1PreparedSnapshot prepared,
) {
  final inner = prepared.preparedSnapshot;
  for (final key in pdvV1PreparedSnapshotIdentityRequiredKeys) {
    if (!inner.containsKey(key)) {
      return false;
    }
  }

  final operationId = inner[pdvV1PreparedSnapshotIdentityOperationIdKey];
  if (operationId is! String || operationId != prepared.operationId) {
    return false;
  }

  final saleId = inner[pdvV1PreparedSnapshotIdentitySaleIdKey];
  if (saleId is! String || saleId != prepared.saleId) {
    return false;
  }

  final lojaId = inner[pdvV1PreparedSnapshotIdentityLojaIdKey];
  if (lojaId is! String || lojaId != prepared.lojaId) {
    return false;
  }

  final origem = inner[pdvV1PreparedSnapshotIdentityOrigemKey];
  if (origem is! String || origem != prepared.origemProtocol) {
    return false;
  }

  final protocolVersion =
      inner[pdvV1PreparedSnapshotIdentityProtocolVersionKey];
  if (protocolVersion is! int || protocolVersion != prepared.protocolVersion) {
    return false;
  }

  final snapshotHash = inner[pdvV1PreparedSnapshotIdentitySnapshotHashKey];
  if (snapshotHash is! String || snapshotHash != prepared.snapshotHash) {
    return false;
  }

  final txItemsHash = inner[pdvV1PreparedSnapshotIdentityTxItemsHashKey];
  if (txItemsHash is! String || txItemsHash != prepared.txItemsHash) {
    return false;
  }

  return true;
}

/// Outcomes fechados da aplicação remota orquestrada (R2-B).
enum PdvV1RemoteStockApplyOutcomeKind {
  remoteAppliedJournalAdvanced,
  remoteAlreadyAppliedJournalAdvanced,
  remoteAppliedJournalNotAdvanced,
  remotePendingNoMutation,
  manualRequiredNoMutation,
  journalNotFound,
  journalMalformed,
  staleJournalRevision,
  journalNotEligible,
  preparedSnapshotNotEligible,
}

/// Resultado tipado — sem payload de estoque nem snapshot completo.
class PdvV1RemoteStockApplyResult {
  const PdvV1RemoteStockApplyResult({required this.kind});

  final PdvV1RemoteStockApplyOutcomeKind kind;
}

/// Resultado interno da derivação do plan a partir do journal.
class PdvV1RemoteStockPlanDerivationResult {
  const PdvV1RemoteStockPlanDerivationResult._({
    required this.eligible,
    this.plan,
  });

  const PdvV1RemoteStockPlanDerivationResult.ineligible()
      : this._(eligible: false);

  const PdvV1RemoteStockPlanDerivationResult.eligible(
    PdvV1RemoteStockMarkerPlan plan,
  ) : this._(eligible: true, plan: plan);

  final bool eligible;
  final PdvV1RemoteStockMarkerPlan? plan;
}

/// Deriva [PdvV1RemoteStockMarkerPlan] somente do [PdvV1PreparedSnapshot] persistido.
PdvV1RemoteStockPlanDerivationResult pdvV1DeriveRemoteStockMarkerPlan(
  PdvV1PreparedSnapshot prepared,
) {
  if (prepared.isFiado ||
      prepared.hasCombo ||
      prepared.isEdicao ||
      prepared.isCancelamento) {
    return const PdvV1RemoteStockPlanDerivationResult.ineligible();
  }
  if (prepared.origem != PdvV1InternalOrigin.novaVendaPdvFuture) {
    return const PdvV1RemoteStockPlanDerivationResult.ineligible();
  }

  final snapshot = prepared.preparedSnapshot;
  if (!snapshot.containsKey(pdvV1PreparedSnapshotTxItemsKey)) {
    return const PdvV1RemoteStockPlanDerivationResult.ineligible();
  }

  final rawItems = snapshot[pdvV1PreparedSnapshotTxItemsKey];
  if (rawItems is! List) {
    return const PdvV1RemoteStockPlanDerivationResult.ineligible();
  }
  if (rawItems.length != 1) {
    return const PdvV1RemoteStockPlanDerivationResult.ineligible();
  }

  final rawItem = rawItems.first;
  if (rawItem is! Map) {
    return const PdvV1RemoteStockPlanDerivationResult.ineligible();
  }

  final item = Map<String, dynamic>.from(rawItem);
  final keys = item.keys.toSet();
  if (keys.length != _pdvV1SimpleItemAllowedKeys.length ||
      !keys.containsAll(_pdvV1SimpleItemAllowedKeys)) {
    return const PdvV1RemoteStockPlanDerivationResult.ineligible();
  }

  final productIdRaw = item[pdvV1PreparedSnapshotSimpleItemProductIdKey];
  if (productIdRaw is! String || productIdRaw.trim().isEmpty) {
    return const PdvV1RemoteStockPlanDerivationResult.ineligible();
  }

  final quantidadeRaw = item[pdvV1PreparedSnapshotSimpleItemQuantidadeKey];
  if (quantidadeRaw is! int || quantidadeRaw <= 0) {
    return const PdvV1RemoteStockPlanDerivationResult.ineligible();
  }

  try {
    final plan = PdvV1RemoteStockMarkerPlan(
      operationId: prepared.operationId,
      saleId: prepared.saleId,
      lojaId: prepared.lojaId,
      origem: prepared.origemProtocol,
      protocolVersion: prepared.protocolVersion,
      snapshotHash: prepared.snapshotHash,
      txItemsHash: prepared.txItemsHash,
      stockDocumentId: productIdRaw,
      quantityToDebit: quantidadeRaw,
    );
    return PdvV1RemoteStockPlanDerivationResult.eligible(plan);
  } catch (_) {
    return const PdvV1RemoteStockPlanDerivationResult.ineligible();
  }
}
