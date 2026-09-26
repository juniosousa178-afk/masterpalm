// Espelho remoto de contas a pagar — fase 1B.
// SHADOW ONLY. Hive continua a autoridade. Não marca pago, não cancela,
// não cria parcela e não gera lançamento financeiro.
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
  });

  final String storeId;
  final List<ContaPagarMirrorRow> rows;
  final int total;
  final int matched;
  final int mismatched;
  final int localOnly;
  final int remoteOnly;
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

  static bool get isEnabled =>
      debugEnabledOverride ?? FinancialV2Flags.payablesRemoteMirrorEnabled;

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  static Future<ContaPagarMirrorWriteResult> mirrorIfEnabled({
    required String storeId,
    required ContaPagar conta,
  }) async {
    if (!isEnabled) {
      return const ContaPagarMirrorWriteResult(
        ContaPagarMirrorWriteKind.skippedFlagOff,
      );
    }
    try {
      return await mirrorUpsert(storeId: storeId, conta: conta);
    } catch (e) {
      debugPrint('[CP-MIRROR] sombra falhou: $e');
      return const ContaPagarMirrorWriteResult(
        ContaPagarMirrorWriteKind.skippedFlagOff,
      );
    }
  }

  static Future<ContaPagarMirrorWriteResult> mirrorUpsert({
    required String storeId,
    required ContaPagar conta,
  }) async {
    if (!isEnabled) {
      return const ContaPagarMirrorWriteResult(
        ContaPagarMirrorWriteKind.skippedFlagOff,
      );
    }
    final gate = _gate(storeId, conta);
    if (gate != null) return gate;
    final remoteId = payableRemoteDocId(conta.id);
    final ref = _ref(storeId.trim(), remoteId);
    final existing = await ref.get();
    final incoming = _businessFields(conta, deleted: false);

    if (existing.exists) {
      final data = existing.data() ?? <String, dynamic>{};
      if (_identityConflict(data, storeId.trim(), remoteId)) {
        return ContaPagarMirrorWriteResult(
          ContaPagarMirrorWriteKind.rejectedIdentity,
          remoteId: remoteId,
        );
      }
      if (_isTerminal(data) && _reopensTerminal(data, conta)) {
        return ContaPagarMirrorWriteResult(
          ContaPagarMirrorWriteKind.rejectedTerminal,
          remoteId: remoteId,
        );
      }
      if (_sameBusiness(data, incoming)) {
        return ContaPagarMirrorWriteResult(
          ContaPagarMirrorWriteKind.noChange,
          remoteId: remoteId,
        );
      }
      final remoteMs = _millis(data['localUpdatedAtMs']);
      if (remoteMs != null &&
          conta.atualizadoEm.millisecondsSinceEpoch < remoteMs) {
        return ContaPagarMirrorWriteResult(
          ContaPagarMirrorWriteKind.rejectedStale,
          remoteId: remoteId,
        );
      }
      final revision = (_millis(data['mirrorRevision']) ?? 0) + 1;
      await ref.set(_envelope(conta, remoteId, revision, deletedAt: null));
      return ContaPagarMirrorWriteResult(
        ContaPagarMirrorWriteKind.applied,
        remoteId: remoteId,
      );
    }

    await ref.set(_envelope(conta, remoteId, 1, deletedAt: null));
    return ContaPagarMirrorWriteResult(
      ContaPagarMirrorWriteKind.applied,
      remoteId: remoteId,
    );
  }

  static Future<ContaPagarMirrorWriteResult> mirrorSoftDelete({
    required String storeId,
    required ContaPagar conta,
    DateTime? deletedAt,
  }) async {
    if (!isEnabled) {
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
    throw StateError('Bootstrap de contas a pagar não executa na fase 1B.');
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
