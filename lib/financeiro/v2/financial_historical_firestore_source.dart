import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../models/fechamento_mensal.dart';
import '../../models/lancamento_financeiro.dart';
import '../../models/venda.dart';
import '../../services/firestore_paths.dart';
import 'brazil_business_date.dart';
import 'financial_historical_visibility.dart';
import 'financial_month.dart';

class FinancialHistoricalUnavailable implements Exception {
  const FinancialHistoricalUnavailable();
}

/// Leituras remotas de histórico. Não grava Hive nem Firestore.
class FinancialHistoricalSources {
  static FinancialHistoricalRemoteSource? debugOverride;

  static FinancialHistoricalRemoteSource get current =>
      debugOverride ?? FirestoreFinancialHistoricalSource();
}

abstract class FinancialHistoricalRemoteSource {
  Future<FinancialMonthRange> loadRange({
    required String storeId,
    required DateTime now,
  });

  Future<List<LancamentoFinanceiro>> loadLaunches({
    required String storeId,
    required FinancialMonth month,
  });

  /// Lançamentos do intervalo, sem filtrar pela data de pagamento.
  /// A DRE classifica pela competência. Não grava.
  Future<List<LancamentoFinanceiro>> loadLaunchesInUtcRange({
    required String storeId,
    required DateTime startUtcInclusive,
    required DateTime endExclusiveUtc,
  });

  Future<FechamentoMensal?> loadClosure({
    required String storeId,
    required FinancialMonth month,
  });

  Future<List<FechamentoMensal>> loadClosuresForYear({
    required String storeId,
    required int year,
  });

  Future<List<Venda>> loadSales({
    required String storeId,
    required DateTime startUtcInclusive,
    required DateTime endExclusiveUtc,
  });
}

class FirestoreFinancialHistoricalSource
    implements FinancialHistoricalRemoteSource {
  FirestoreFinancialHistoricalSource({FirebaseFirestore? firestore})
      : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  static const hiveWritesFromRead = 0;

  FirebaseFirestore get _db {
    if (Firebase.apps.isEmpty) {
      throw const FinancialHistoricalUnavailable();
    }
    return _firestore ?? FirebaseFirestore.instance;
  }

  CollectionReference<Map<String, dynamic>> _collection(
    String storeId,
    String name,
  ) {
    final id = storeId.trim();
    if (id.isEmpty) throw const FinancialHistoricalUnavailable();
    return _db.collection('lojas').doc(id).collection(name);
  }

  @override
  Future<FinancialMonthRange> loadRange({
    required String storeId,
    required DateTime now,
  }) async {
    final closureAsc = await _edgeClosure(storeId, descending: false);
    final closureDesc = await _edgeClosure(storeId, descending: true);
    final saleAsc = await _edgeInstant(
      storeId,
      FSPaths.estoqueVendasCol,
      'data',
      descending: false,
    );
    final saleDesc = await _edgeInstant(
      storeId,
      FSPaths.estoqueVendasCol,
      'data',
      descending: true,
    );
    final launchAsc = await _edgeInstant(
      storeId,
      'lancamentos_financeiros',
      'dataLancamento',
      descending: false,
    );
    final launchDesc = await _edgeInstant(
      storeId,
      'lancamentos_financeiros',
      'dataLancamento',
      descending: true,
    );
    return FinancialMonthRange.resolve(
      evidence: [
        if (closureAsc != null) closureAsc,
        if (closureDesc != null) closureDesc,
        if (saleAsc != null) FinancialMonth.fromInstant(saleAsc),
        if (saleDesc != null) FinancialMonth.fromInstant(saleDesc),
        if (launchAsc != null) FinancialMonth.fromInstant(launchAsc),
        if (launchDesc != null) FinancialMonth.fromInstant(launchDesc),
      ],
      now: now,
    );
  }

  Future<FinancialMonth?> _edgeClosure(
    String storeId, {
    required bool descending,
  }) async {
    final snap = await _collection(storeId, 'fechamentos_mensais')
        .orderBy(FieldPath.documentId, descending: descending)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    final parsed = monthFromClosureDocumentId(doc.id, storeId);
    if (parsed == null) return null;
    final loja = (doc.data()['lojaId'] ?? '').toString().trim();
    if (loja.isNotEmpty && loja != storeId.trim()) return null;
    return parsed;
  }

  Future<DateTime?> _edgeInstant(
    String storeId,
    String collection,
    String field, {
    required bool descending,
  }) async {
    final snap = await _collection(storeId, collection)
        .orderBy(field, descending: descending)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final data = snap.docs.first.data();
    final loja = (data['lojaId'] ?? '').toString().trim();
    if (loja.isNotEmpty && loja != storeId.trim()) return null;
    return _timestamp(data[field]);
  }

  @override
  Future<List<LancamentoFinanceiro>> loadLaunches({
    required String storeId,
    required FinancialMonth month,
  }) async {
    final col = _collection(storeId, 'lancamentos_financeiros');
    final start = Timestamp.fromDate(month.startUtcInclusive);
    final end = Timestamp.fromDate(month.endExclusiveUtc);
    final byLaunch = await col
        .where('dataLancamento', isGreaterThanOrEqualTo: start)
        .where('dataLancamento', isLessThan: end)
        .get();
    final byPayment = await col
        .where('dataPagamento', isGreaterThanOrEqualTo: start)
        .where('dataPagamento', isLessThan: end)
        .get();
    final parsed = <String, LancamentoFinanceiro>{};
    for (final doc in [...byLaunch.docs, ...byPayment.docs]) {
      final launch = lancamentoFromRemoteRead(
        docId: doc.id,
        data: doc.data(),
        storeId: storeId,
      );
      if (launch == null) continue;
      if (!month.containsInstant(launch.dataEfetivaPagamentoOuLancamento)) {
        continue;
      }
      parsed.putIfAbsent(launch.id, () => launch);
    }
    return parsed.values.toList();
  }

  @override
  Future<List<LancamentoFinanceiro>> loadLaunchesInUtcRange({
    required String storeId,
    required DateTime startUtcInclusive,
    required DateTime endExclusiveUtc,
  }) async {
    final col = _collection(storeId, 'lancamentos_financeiros');
    final start = Timestamp.fromDate(startUtcInclusive);
    final end = Timestamp.fromDate(endExclusiveUtc);
    final byLaunch = await col
        .where('dataLancamento', isGreaterThanOrEqualTo: start)
        .where('dataLancamento', isLessThan: end)
        .get();
    final byPayment = await col
        .where('dataPagamento', isGreaterThanOrEqualTo: start)
        .where('dataPagamento', isLessThan: end)
        .get();
    final parsed = <String, LancamentoFinanceiro>{};
    for (final doc in [...byLaunch.docs, ...byPayment.docs]) {
      final launch = lancamentoFromRemoteRead(
        docId: doc.id,
        data: doc.data(),
        storeId: storeId,
      );
      if (launch == null) continue;
      parsed.putIfAbsent(launch.id, () => launch);
    }
    return parsed.values.toList();
  }

  @override
  Future<FechamentoMensal?> loadClosure({
    required String storeId,
    required FinancialMonth month,
  }) async {
    final docId = closureDocumentId(storeId, month);
    final snap =
        await _collection(storeId, 'fechamentos_mensais').doc(docId).get();
    if (!snap.exists) return null;
    return fechamentoFromRemoteRead(
      docId: snap.id,
      data: snap.data() ?? const {},
      storeId: storeId,
    );
  }

  @override
  Future<List<FechamentoMensal>> loadClosuresForYear({
    required String storeId,
    required int year,
  }) async {
    final start = '$year-01-';
    final end = '${year + 1}-01-';
    final snap = await _collection(storeId, 'fechamentos_mensais')
        .orderBy(FieldPath.documentId)
        .startAt([start])
        .endBefore([end])
        .get();
    final out = <FechamentoMensal>[];
    for (final doc in snap.docs) {
      final parsed = fechamentoFromRemoteRead(
        docId: doc.id,
        data: doc.data(),
        storeId: storeId,
      );
      if (parsed != null && parsed.ano == year) out.add(parsed);
    }
    return out;
  }

  @override
  Future<List<Venda>> loadSales({
    required String storeId,
    required DateTime startUtcInclusive,
    required DateTime endExclusiveUtc,
  }) async {
    final snap = await _collection(storeId, FSPaths.estoqueVendasCol)
        .where(
          'data',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startUtcInclusive),
        )
        .where('data', isLessThan: Timestamp.fromDate(endExclusiveUtc))
        .get();
    final out = <Venda>[];
    for (final doc in snap.docs) {
      final venda = vendaFromRemoteRead(
        docId: doc.id,
        data: doc.data(),
        storeId: storeId,
      );
      if (venda != null) out.add(venda);
    }
    return out;
  }
}

DateTime? _timestamp(dynamic value) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  return null;
}

double? _double(dynamic value) {
  if (value is num) return value.toDouble();
  return null;
}

LancamentoFinanceiro? lancamentoFromRemoteRead({
  required String docId,
  required Map<String, dynamic> data,
  required String storeId,
}) {
  final valor = _double(data['valor']);
  final dataLancamento = _timestamp(data['dataLancamento']);
  if (valor == null || dataLancamento == null) return null;
  final loja = (data['lojaId'] ?? '').toString().trim();
  if (loja.isNotEmpty && loja != storeId.trim()) return null;
  final status = (data['status'] ?? '').toString().trim();
  final tipo = (data['tipo'] ?? '').toString().trim();
  final categoria = (data['categoria'] ?? '').toString().trim();
  return LancamentoFinanceiro(
    id: docId,
    lojaId: storeId.trim(),
    descricao: (data['descricao'] ?? '').toString(),
    valor: valor,
    tipo: tipo,
    categoria: categoria,
    subcategoria: (data['subcategoria'] ?? '').toString(),
    status: status,
    formaPagamento: (data['formaPagamento'] ?? '').toString(),
    fornecedor: (data['fornecedor'] ?? '').toString(),
    observacao: (data['observacao'] ?? '').toString(),
    dataLancamento: dataLancamento,
    dataPagamento: _timestamp(data['dataPagamento']),
    competenciaMes: data['competenciaMes'] is num
        ? (data['competenciaMes'] as num).toInt()
        : BrazilBusinessDate.dateOnly(dataLancamento).month,
    competenciaAno: data['competenciaAno'] is num
        ? (data['competenciaAno'] as num).toInt()
        : BrazilBusinessDate.dateOnly(dataLancamento).year,
    recorrente: data['recorrente'] == true,
    origem: (data['origem'] ?? '').toString(),
    usuarioId: (data['usuarioId'] ?? '').toString(),
    usuarioNome: (data['usuarioNome'] ?? '').toString(),
    centroCusto: (data['centroCusto'] ?? '').toString(),
    anexoComprovante: (data['anexoComprovante'] ?? '').toString(),
    referenciaExterna: (data['referenciaExterna'] ?? '').toString(),
    solicitarAtualizacaoEstoque: data['solicitarAtualizacaoEstoque'] == true,
  );
}

FechamentoMensal? fechamentoFromRemoteRead({
  required String docId,
  required Map<String, dynamic> data,
  required String storeId,
}) {
  final month = monthFromClosureDocumentId(docId, storeId);
  if (month == null) return null;
  final loja = (data['lojaId'] ?? '').toString().trim();
  if (loja.isNotEmpty && loja != storeId.trim()) return null;
  final venda = _double(data['vendaTotal']);
  if (venda == null) return null;
  final fechado = _timestamp(data['dataFechamento']) ??
      _timestamp(data['updatedAt']) ??
      DateTime.utc(month.year, month.month, 1);
  return FechamentoMensal(
    ano: month.year,
    mes: month.month,
    totalDinheiro: _double(data['totalDinheiro']) ?? 0,
    totalPix: _double(data['totalPix']) ?? 0,
    totalCartao: _double(data['totalCartao']) ?? 0,
    vendaTotal: venda,
    custoTotal: _double(data['custoTotal']) ?? 0,
    taxasTotal: _double(data['taxasTotal']) ?? 0,
    lucroTotal: _double(data['lucroTotal']) ?? 0,
    fechadoEm: fechado,
    lojaId: storeId.trim(),
  );
}

Venda? vendaFromRemoteRead({
  required String docId,
  required Map<String, dynamic> data,
  required String storeId,
}) {
  final total = _double(data['total']);
  final raw = _timestamp(data['data']);
  if (total == null || raw == null) return null;
  final loja = (data['lojaId'] ?? '').toString().trim();
  if (loja.isNotEmpty && loja != storeId.trim()) return null;
  final day = businessDayFromUtc(raw);
  return Venda(
    preco: _double(data['preco']) ?? total,
    produtosDescricao: (data['produtosDescricao'] ?? '').toString(),
    quantidade: data['quantidade'] is num
        ? (data['quantidade'] as num).toInt()
        : 1,
    clienteNome: (data['clienteNome'] ?? '').toString(),
    total: total,
    formasPagamento: (data['formasPagamento'] ?? '').toString(),
    data: day,
    vendedor: (data['vendedor'] ?? '').toString(),
    observacao: (data['observacao'] ?? '').toString(),
    pagamentoDinheiro: _double(data['pagamentoDinheiro']) ?? 0,
    pagamentoPix: _double(data['pagamentoPix']) ?? 0,
    pagamentoCartao: _double(data['pagamentoCartao']) ?? 0,
    taxas: _double(data['taxas']) ?? 0,
    custoProdutos: _double(data['custoProdutos']) ?? 0,
    desconto: _double(data['desconto']) ?? 0,
    descontoValor: _double(data['descontoValor']) ?? 0,
    lojaId: storeId.trim(),
    idFirebase: docId,
    cancelada: data['cancelada'] == true,
    estornada: data['estornada'] == true,
    statusVenda: data['statusVenda']?.toString(),
  );
}
