// Espelho remoto de contas a pagar — fase 1B, piloto 1C por loja.
// SHADOW ONLY. Hive continua a autoridade. Não marca pago, não cancela,
// não cria parcela e não gera lançamento financeiro.
// A flag global fica falsa. Só a loja piloto, com o documento
// financial_v2_pilot/payables ligado, grava o espelho.
//
// Coleção nova: lojas/{storeId}/contas_pagar/{payableId}
// Não havia coleção Firestore com este nome (a box Hive é contas_pagar_{lojaId}).
//
// Id remoto = id local. Parcelas de compra já usam `{compraId}_p{n}`.
//
// Migração futura, sem saltar etapas:
// 1. Hive autoridade + espelho sombra (esta fase)
// 2. comparar aparelhos
// 3. leitura remota autoritativa e Hive como cache
// 4. retirar autoridade local

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/conta_pagar.dart';
import '../../models/conta_pagar_constants.dart';
import 'financial_v2_flags.dart';

const int kContaPagarMirrorSchemaVersion = 1;
const String kContaPagarMirrorSource = 'hive_conta_pagar';
const String kContasPagarMirrorCollection = 'contas_pagar';
const String kPayablesPilotCollection = 'financial_v2_pilot';
const String kPayablesPilotDocId = 'payables';

/// O espelho nunca grava de volta no Hive.
const bool kPayableRemoteToLocalSyncEnabled = false;

abstract final class PayableMirrorMismatchType {
  static const localNotMirrored = 'LOCAL_NOT_MIRRORED';
  static const remoteMissing = 'REMOTE_MISSING';
  static const fieldMismatch = 'FIELD_MISMATCH';
  static const remoteNewer = 'REMOTE_NEWER';
  static const localNewer = 'LOCAL_NEWER';
  static const terminalConflict = 'TERMINAL_CONFLICT';
  static const identityConflict = 'IDENTITY_CONFLICT';
  static const remoteOnly = 'REMOTE_ONLY';
}

enum ContaPagarMirrorWriteKind {
  skippedFlagOff,
  applied,
  noChange,
  rejectedTerminal,
  rejectedStale,
  rejectedTenant,
  rejectedIdentity,
  failure,
}

class PayableMirrorDiagnostic {
  const PayableMirrorDiagnostic({
    required this.event,
    required this.storeId,
    required this.payableId,
    required this.localUpdatedAt,
    required this.remoteMirroredAt,
    required this.result,
  });

  final String event;
  final String storeId;
  final String payableId;
  final int? localUpdatedAt;
  final int? remoteMirroredAt;
  final String result;
}

class ContaPagarMirrorWriteResult {
  const ContaPagarMirrorWriteResult(this.kind, {this.remoteId});

  final ContaPagarMirrorWriteKind kind;
  final String? remoteId;

  bool get wrote => kind == ContaPagarMirrorWriteKind.applied;
}

String payableRemoteDocId(String localId) {
  final id = localId.trim();
  if (id.isEmpty || id.contains('/')) {
    throw ArgumentError('Id local de conta a pagar inválido para o espelho.');
  }
  return id;
}

bool contaPagarMirrorTerminalStatus(String status) {
  final s = status.trim().toLowerCase();
  return s == ContaPagarStatus.pago || s == ContaPagarStatus.cancelado;
}

class ContaPagarMirrorRow {
  const ContaPagarMirrorRow({
    required this.localId,
    required this.remoteId,
    required this.localStatus,
    required this.remoteStatus,
    required this.localAmount,
    required this.remoteAmount,
    required this.localDueDate,
    required this.remoteDueDate,
    required this.match,
    required this.mismatchType,
  });

  final String? localId;
  final String? remoteId;
  final String? localStatus;
  final String? remoteStatus;
  final double? localAmount;
  final double? remoteAmount;
  final DateTime? localDueDate;
  final DateTime? remoteDueDate;
  final bool match;
  final String? mismatchType;
}

class ContaPagarMirrorComparison {
  const ContaPagarMirrorComparison({
    required this.storeId,
    required this.rows,
    required this.total,
    required this.matched,
    required this.mismatched,
    required this.localOnly,
    required this.remoteOnly,
    this.purchaseInstallmentDuplicateCount = 0,
  });

  final String storeId;
  final List<ContaPagarMirrorRow> rows;
  final int total;
  final int matched;
  final int mismatched;
  final int localOnly;
  final int remoteOnly;
  final int purchaseInstallmentDuplicateCount;

  int countOf(String mismatchType) =>
      rows.where((row) => row.mismatchType == mismatchType).length;

  double get localMirroredAmountSum => rows
      .where((row) => row.localId != null && row.remoteId != null)
      .fold<double>(0, (sum, row) => sum + (row.localAmount ?? 0));

  double get remoteMirroredAmountSum => rows
      .where((row) => row.localId != null && row.remoteId != null)
      .fold<double>(0, (sum, row) => sum + (row.remoteAmount ?? 0));
}

class ContaPagarMirrorBootstrapPreview {
  const ContaPagarMirrorBootstrapPreview({
    required this.storeId,
    required this.count,
    required this.amountSum,
    required this.remoteIds,
  });

  final String storeId;
  final int count;
  final double amountSum;
  final List<String> remoteIds;

  bool get writesPerformed => false;
}

abstract final class ContaPagarRemoteMirrorService {
  static FirebaseFirestore? debugFirestoreOverride;
  static bool? debugEnabledOverride;
  static String? debugPilotStoreIdOverride;
  static Future<void> Function()? debugWriteFault;
  static final List<PayableMirrorDiagnostic> debugDiagnostics = [];

  static bool get isEnabled =>
      debugEnabledOverride ?? FinancialV2Flags.payablesRemoteMirrorEnabled;

  static String get pilotStoreId => (debugPilotStoreIdOverride ??
          FinancialV2Flags.payablesRemoteMirrorPilotStoreId)
      .trim();

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  static void debugResetDiagnostics() => debugDiagnostics.clear();

  /// Flag global falsa. Só a loja piloto, e só com o documento remoto ligado.
  static Future<bool> enabledForStore(String storeId) async {
    if (debugEnabledOverride != null) return debugEnabledOverride!;
    if (FinancialV2Flags.payablesRemoteMirrorEnabled) return true;
    final store = storeId.trim();
    final pilot = pilotStoreId;
    if (pilot.isEmpty || store != pilot) return false;
    try {
      final snap = await _db
          .collection('lojas')
          .doc(store)
          .collection(kPayablesPilotCollection)
          .doc(kPayablesPilotDocId)
          .get();
      final data = snap.data();
      if (data == null) return false;
      final docStore = (data['storeId'] ?? '').toString().trim();
      if (docStore != store) return false;
      return data['payablesRemoteMirrorEnabled'] == true;
    } catch (e) {
      _record(
        event: 'PAYABLE_MIRROR_FAILURE',
        storeId: store,
        payableId: '',
        localUpdatedAt: null,
        remoteMirroredAt: null,
        result: 'SHADOW_MIRROR_FAILURE',
      );
      return false;
    }
  }

  static Future<ContaPagarMirrorWriteResult> mirrorIfEnabled({
    required String storeId,
    required ContaPagar conta,
  }) async {
    try {
      return await mirrorUpsert(storeId: storeId, conta: conta);
    } catch (e) {
      _record(
        event: 'PAYABLE_MIRROR_FAILURE',
        storeId: storeId.trim(),
        payableId: conta.id.trim(),
        localUpdatedAt: conta.atualizadoEm.millisecondsSinceEpoch,
        remoteMirroredAt: null,
        result: 'SHADOW_MIRROR_FAILURE',
      );
      return ContaPagarMirrorWriteResult(
        ContaPagarMirrorWriteKind.failure,
        remoteId: conta.id.trim(),
      );
    }
  }

  static Future<ContaPagarMirrorWriteResult> mirrorUpsert({
    required String storeId,
    required ContaPagar conta,
  }) async {
    if (!await enabledForStore(storeId)) {
      return const ContaPagarMirrorWriteResult(
        ContaPagarMirrorWriteKind.skippedFlagOff,
      );
    }
    _record(
      event: 'PAYABLE_MIRROR_ATTEMPT',
      storeId: storeId.trim(),
      payableId: conta.id.trim(),
      localUpdatedAt: conta.atualizadoEm.millisecondsSinceEpoch,
      remoteMirroredAt: null,
      result: 'attempt',
    );
    final gate = _gate(storeId, conta);
    if (gate != null) return _finish(gate, storeId: storeId, conta: conta);
    final remoteId = payableRemoteDocId(conta.id);
    final ref = _ref(storeId.trim(), remoteId);
    final existing = await ref.get();
    final incoming = _businessFields(conta, deleted: false);

    if (existing.exists) {
      final data = existing.data() ?? <String, dynamic>{};
      if (_identityConflict(data, storeId.trim(), remoteId)) {
        return _finish(
          ContaPagarMirrorWriteResult(
            ContaPagarMirrorWriteKind.rejectedIdentity,
            remoteId: remoteId,
          ),
          storeId: storeId,
          conta: conta,
        );
      }
      if (_isTerminal(data) && _reopensTerminal(data, conta)) {
        return _finish(
          ContaPagarMirrorWriteResult(
            ContaPagarMirrorWriteKind.rejectedTerminal,
            remoteId: remoteId,
          ),
          storeId: storeId,
          conta: conta,
          remoteMirroredAt: _millis(data['localUpdatedAtMs']),
        );
      }
      if (_sameBusiness(data, incoming)) {
        return _finish(
          ContaPagarMirrorWriteResult(
            ContaPagarMirrorWriteKind.noChange,
            remoteId: remoteId,
          ),
          storeId: storeId,
          conta: conta,
          remoteMirroredAt: _millis(data['localUpdatedAtMs']),
        );
      }
      final remoteMs = _millis(data['localUpdatedAtMs']);
      if (remoteMs != null &&
          conta.atualizadoEm.millisecondsSinceEpoch < remoteMs) {
        return _finish(
          ContaPagarMirrorWriteResult(
            ContaPagarMirrorWriteKind.rejectedStale,
            remoteId: remoteId,
          ),
          storeId: storeId,
          conta: conta,
          remoteMirroredAt: remoteMs,
        );
      }
      final revision = (_millis(data['mirrorRevision']) ?? 0) + 1;
      if (debugWriteFault != null) await debugWriteFault!();
      final keptDeletedAt = _date(data['deletedAt']);
      await ref.set(_envelope(
        conta,
        remoteId,
        revision,
        deletedAt: keptDeletedAt,
      ));
      return _finish(
        ContaPagarMirrorWriteResult(
          ContaPagarMirrorWriteKind.applied,
          remoteId: remoteId,
        ),
        storeId: storeId,
        conta: conta,
      );
    }

    if (debugWriteFault != null) await debugWriteFault!();
    await ref.set(_envelope(conta, remoteId, 1, deletedAt: null));
    return _finish(
      ContaPagarMirrorWriteResult(
        ContaPagarMirrorWriteKind.applied,
        remoteId: remoteId,
      ),
      storeId: storeId,
      conta: conta,
    );
  }

  static Future<ContaPagarMirrorWriteResult> mirrorSoftDelete({
    required String storeId,
    required ContaPagar conta,
    DateTime? deletedAt,
  }) async {
    if (!await enabledForStore(storeId)) {
      return const ContaPagarMirrorWriteResult(
        ContaPagarMirrorWriteKind.skippedFlagOff,
      );
    }
    final gate = _gate(storeId, conta);
    if (gate != null) return gate;
    final remoteId = payableRemoteDocId(conta.id);
    final ref = _ref(storeId.trim(), remoteId);
    final existing = await ref.get();
    if (existing.exists && _date(existing.data()?['deletedAt']) != null) {
      return ContaPagarMirrorWriteResult(
        ContaPagarMirrorWriteKind.noChange,
        remoteId: remoteId,
      );
    }
    final revision = existing.exists
        ? (_millis(existing.data()?['mirrorRevision']) ?? 0) + 1
        : 1;
    if (debugWriteFault != null) await debugWriteFault!();
    await ref.set(_envelope(
      conta,
      remoteId,
      revision,
      deletedAt: deletedAt ?? DateTime.now().toUtc(),
    ));
    return ContaPagarMirrorWriteResult(
      ContaPagarMirrorWriteKind.applied,
      remoteId: remoteId,
    );
  }

  static Future<ContaPagarMirrorComparison> compare({
    required String storeId,
    required Iterable<ContaPagar> local,
  }) async {
    final store = storeId.trim();
    if (store.isEmpty) {
      throw ArgumentError('storeId explícito é obrigatório.');
    }
    final locals = <String, ContaPagar>{
      for (final c in local)
        if (c.lojaId.trim() == store) payableRemoteDocId(c.id): c,
    };
    final remoteSnap = await _db
        .collection('lojas')
        .doc(store)
        .collection(kContasPagarMirrorCollection)
        .get();
    final remotes = <String, Map<String, dynamic>>{};
    for (final doc in remoteSnap.docs) {
      final data = doc.data();
      final docStore =
          (data['storeId'] ?? data['lojaId'] ?? '').toString().trim();
      if (docStore.isNotEmpty && docStore != store) continue;
      remotes[doc.id] = data;
    }

    final ids = {...locals.keys, ...remotes.keys}.toList()..sort();
    final rows = <ContaPagarMirrorRow>[];
    var matched = 0;
    var localOnly = 0;
    var remoteOnly = 0;

    for (final id in ids) {
      final item = locals[id];
      final remote = remotes[id];
      if (item != null && remote == null) {
        localOnly++;
        rows.add(ContaPagarMirrorRow(
          localId: item.id,
          remoteId: null,
          localStatus: item.status,
          remoteStatus: null,
          localAmount: item.valorParcela,
          remoteAmount: null,
          localDueDate: item.dataVencimento,
          remoteDueDate: null,
          match: false,
          mismatchType: PayableMirrorMismatchType.localNotMirrored,
        ));
        continue;
      }
      if (item == null && remote != null) {
        remoteOnly++;
        rows.add(ContaPagarMirrorRow(
          localId: null,
          remoteId: id,
          localStatus: null,
          remoteStatus: _text(remote['status']),
          localAmount: null,
          remoteAmount: _double(remote['valorParcela']),
          localDueDate: null,
          remoteDueDate: _date(remote['dataVencimento']),
          match: false,
          mismatchType: PayableMirrorMismatchType.remoteOnly,
        ));
        continue;
      }
      final localConta = item!;
      final data = remote!;
      if (_identityConflict(data, store, id)) {
        rows.add(_mismatchRow(
          localConta,
          id,
          data,
          PayableMirrorMismatchType.identityConflict,
        ));
        continue;
      }
      if (_isTerminal(data) && _reopensTerminal(data, localConta)) {
        rows.add(_mismatchRow(
          localConta,
          id,
          data,
          PayableMirrorMismatchType.terminalConflict,
        ));
        continue;
      }
      final deleted = _date(data['deletedAt']) != null;
      if (_sameBusiness(data, _businessFields(localConta, deleted: deleted))) {
        matched++;
        rows.add(_mismatchRow(localConta, id, data, null, match: true));
        continue;
      }
      final remoteMs = _millis(data['localUpdatedAtMs']);
      final localMs = localConta.atualizadoEm.millisecondsSinceEpoch;
      var type = PayableMirrorMismatchType.fieldMismatch;
      if (remoteMs != null && localMs > remoteMs) {
        type = PayableMirrorMismatchType.localNewer;
      } else if (remoteMs != null && localMs < remoteMs) {
        type = PayableMirrorMismatchType.remoteNewer;
      }
      rows.add(_mismatchRow(localConta, id, data, type));
    }

    return ContaPagarMirrorComparison(
      storeId: store,
      rows: rows,
      total: ids.length,
      matched: matched,
      mismatched: rows.where((e) => !e.match).length,
      localOnly: localOnly,
      remoteOnly: remoteOnly,
      purchaseInstallmentDuplicateCount: _purchaseDuplicates(remotes),
    );
  }

  static ContaPagarMirrorBootstrapPreview preview({
    required String storeId,
    required Iterable<ContaPagar> local,
  }) {
    final store = storeId.trim();
    if (store.isEmpty) {
      throw ArgumentError('storeId explícito é obrigatório.');
    }
    final ids = <String>[];
    var sum = 0.0;
    for (final c in local) {
      if (c.lojaId.trim() != store) continue;
      ids.add(payableRemoteDocId(c.id));
      sum += c.valorParcela;
    }
    ids.sort();
    return ContaPagarMirrorBootstrapPreview(
      storeId: store,
      count: ids.length,
      amountSum: sum,
      remoteIds: ids,
    );
  }

  static Future<void> executeBootstrap() async {
    throw StateError('Bootstrap de contas a pagar não executa na fase 1C.');
  }

  static ContaPagarMirrorWriteResult _finish(
    ContaPagarMirrorWriteResult result, {
    required String storeId,
    required ContaPagar conta,
    int? remoteMirroredAt,
  }) {
    final event = switch (result.kind) {
      ContaPagarMirrorWriteKind.applied => 'PAYABLE_MIRROR_SUCCESS',
      ContaPagarMirrorWriteKind.noChange => 'PAYABLE_MIRROR_NO_CHANGE',
      ContaPagarMirrorWriteKind.rejectedStale ||
      ContaPagarMirrorWriteKind.rejectedTerminal =>
        'PAYABLE_MIRROR_REJECTED_OLDER',
      ContaPagarMirrorWriteKind.failure => 'PAYABLE_MIRROR_FAILURE',
      _ => 'PAYABLE_MIRROR_FAILURE',
    };
    _record(
      event: event,
      storeId: storeId.trim(),
      payableId: conta.id.trim(),
      localUpdatedAt: conta.atualizadoEm.millisecondsSinceEpoch,
      remoteMirroredAt: remoteMirroredAt,
      result: result.kind.name,
    );
    return result;
  }

  static void _record({
    required String event,
    required String storeId,
    required String payableId,
    required int? localUpdatedAt,
    required int? remoteMirroredAt,
    required String result,
  }) {
    debugDiagnostics.add(PayableMirrorDiagnostic(
      event: event,
      storeId: storeId,
      payableId: payableId,
      localUpdatedAt: localUpdatedAt,
      remoteMirroredAt: remoteMirroredAt,
      result: result,
    ));
    debugPrint(
      '[$event] storeId=$storeId payableId=$payableId '
      'localUpdatedAt=$localUpdatedAt remoteMirroredAt=$remoteMirroredAt '
      'result=$result',
    );
  }

  static int _purchaseDuplicates(Map<String, Map<String, dynamic>> remotes) {
    final counts = <String, int>{};
    for (final data in remotes.values) {
      final compra = (data['compraId'] ?? '').toString().trim();
      if (compra.isEmpty) continue;
      final key = '$compra|${data['parcelaNumero']}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    var extra = 0;
    for (final count in counts.values) {
      if (count > 1) extra += count - 1;
    }
    return extra;
  }

  static ContaPagarMirrorWriteResult? _gate(String storeId, ContaPagar conta) {
    final store = storeId.trim();
    if (store.isEmpty || conta.lojaId.trim() != store) {
      return const ContaPagarMirrorWriteResult(
        ContaPagarMirrorWriteKind.rejectedTenant,
      );
    }
    final id = conta.id.trim();
    if (id.isEmpty || id.contains('/')) {
      return const ContaPagarMirrorWriteResult(
        ContaPagarMirrorWriteKind.rejectedIdentity,
      );
    }
    return null;
  }

  static DocumentReference<Map<String, dynamic>> _ref(
    String storeId,
    String remoteId,
  ) {
    return _db
        .collection('lojas')
        .doc(storeId)
        .collection(kContasPagarMirrorCollection)
        .doc(remoteId);
  }

  static ContaPagarMirrorRow _mismatchRow(
    ContaPagar local,
    String remoteId,
    Map<String, dynamic> remote,
    String? mismatch, {
    bool match = false,
  }) {
    return ContaPagarMirrorRow(
      localId: local.id,
      remoteId: remoteId,
      localStatus: local.status,
      remoteStatus: _text(remote['status']),
      localAmount: local.valorParcela,
      remoteAmount: _double(remote['valorParcela']),
      localDueDate: local.dataVencimento,
      remoteDueDate: _date(remote['dataVencimento']),
      match: match,
      mismatchType: mismatch,
    );
  }

  static Map<String, dynamic> _envelope(
    ContaPagar conta,
    String remoteId,
    int revision, {
    required DateTime? deletedAt,
  }) {
    return {
      'storeId': conta.lojaId.trim(),
      'payableId': remoteId,
      'source': kContaPagarMirrorSource,
      'schemaVersion': kContaPagarMirrorSchemaVersion,
      'mirroredAt': Timestamp.fromDate(DateTime.now().toUtc()),
      'mirrorRevision': revision,
      'localUpdatedAtMs': conta.atualizadoEm.millisecondsSinceEpoch,
      'mirrorOnly': true,
      'authoritative': false,
      'deletedAt':
          deletedAt == null ? null : Timestamp.fromDate(deletedAt.toUtc()),
      ..._businessFields(conta, deleted: deletedAt != null),
    };
  }

  static Map<String, dynamic> _businessFields(
    ContaPagar conta, {
    required bool deleted,
  }) {
    return {
      'id': conta.id.trim(),
      'lojaId': conta.lojaId.trim(),
      'fornecedorId': conta.fornecedorId,
      'fornecedorNome': conta.fornecedorNome,
      'compraId': conta.compraId,
      'descricao': conta.descricao,
      'valorTotalCompra': conta.valorTotalCompra,
      'valorParcela': conta.valorParcela,
      'parcelaNumero': conta.parcelaNumero,
      'parcelaTotal': conta.parcelaTotal,
      'dataVencimento': Timestamp.fromDate(conta.dataVencimento.toUtc()),
      'dataPagamento': conta.dataPagamento == null
          ? null
          : Timestamp.fromDate(conta.dataPagamento!.toUtc()),
      'status': conta.status,
      'formaPagamento': conta.formaPagamento,
      'observacao': conta.observacao,
      'lancamentoFinanceiroId': conta.lancamentoFinanceiroId,
      'criadoEm': Timestamp.fromDate(conta.criadoEm.toUtc()),
      'atualizadoEm': Timestamp.fromDate(conta.atualizadoEm.toUtc()),
      'dataCompra': Timestamp.fromDate(conta.dataCompra.toUtc()),
      'idFirebase': conta.idFirebase,
      'deleted': deleted,
    };
  }

  static bool _sameBusiness(
    Map<String, dynamic> remote,
    Map<String, dynamic> incoming,
  ) {
    const keys = [
      'id',
      'lojaId',
      'fornecedorId',
      'fornecedorNome',
      'compraId',
      'descricao',
      'parcelaNumero',
      'parcelaTotal',
      'status',
      'formaPagamento',
      'observacao',
      'lancamentoFinanceiroId',
      'idFirebase',
      'deleted',
    ];
    for (final key in keys) {
      if ('${remote[key]}' != '${incoming[key]}') return false;
    }
    if (!_close(remote['valorTotalCompra'], incoming['valorTotalCompra'])) {
      return false;
    }
    if (!_close(remote['valorParcela'], incoming['valorParcela'])) return false;
    if (!_sameInstant(remote['dataVencimento'], incoming['dataVencimento'])) {
      return false;
    }
    if (!_sameInstant(remote['dataPagamento'], incoming['dataPagamento'])) {
      return false;
    }
    if (!_sameInstant(remote['dataCompra'], incoming['dataCompra'])) {
      return false;
    }
    if (!_sameInstant(remote['criadoEm'], incoming['criadoEm'])) return false;
    if (!_sameInstant(remote['atualizadoEm'], incoming['atualizadoEm'])) {
      return false;
    }
    return true;
  }

  static bool _close(dynamic a, dynamic b) {
    final da = _double(a) ?? 0;
    final db = _double(b) ?? 0;
    return (da - db).abs() <= 0.01;
  }

  static bool _sameInstant(dynamic a, dynamic b) {
    final da = _date(a);
    final db = _date(b);
    if (da == null && db == null) return true;
    if (da == null || db == null) return false;
    return da.toUtc().millisecondsSinceEpoch ==
        db.toUtc().millisecondsSinceEpoch;
  }

  static bool _identityConflict(
    Map<String, dynamic> data,
    String storeId,
    String remoteId,
  ) {
    final payableId = (data['payableId'] ?? '').toString().trim();
    final store = (data['storeId'] ?? '').toString().trim();
    final loja = (data['lojaId'] ?? '').toString().trim();
    if (payableId.isNotEmpty && payableId != remoteId) return true;
    if (store.isNotEmpty && store != storeId) return true;
    if (loja.isNotEmpty && loja != storeId) return true;
    return false;
  }

  static bool _isTerminal(Map<String, dynamic> data) {
    if (_date(data['deletedAt']) != null || data['deleted'] == true) {
      return true;
    }
    return contaPagarMirrorTerminalStatus((data['status'] ?? '').toString());
  }

  static bool _reopensTerminal(Map<String, dynamic> remote, ContaPagar incoming) {
    if (_date(remote['deletedAt']) != null) return true;
    return !contaPagarMirrorTerminalStatus(incoming.status);
  }

  static int? _millis(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  static double? _double(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}');
  }

  static String? _text(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static DateTime? _date(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
