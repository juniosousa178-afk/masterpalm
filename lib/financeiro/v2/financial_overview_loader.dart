import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/conta_pagar.dart';
import '../../models/conta_receber.dart';
import '../../models/lancamento_financeiro.dart';
import '../../models/venda.dart';
import '../../services/conta_pagar_hive_store.dart';
import '../../services/conta_pagar_service.dart';
import '../../services/conta_receber_firestore_service.dart';
import '../../services/financeiro_firestore_service.dart';
import '../../services/firestore_paths.dart';
import '../../services/vendas_firestore_service.dart';
import 'brazil_business_date.dart';
import 'financial_read_model.dart';

/// Portas de leitura. Não há método de escrita.
abstract class FinancialPeriodReads {
  Future<List<Venda>> sales({
    required String storeId,
    required FinancialPeriod period,
  });

  Future<List<LancamentoFinanceiro>> entries({
    required String storeId,
    required FinancialPeriod period,
  });

  Future<List<ContaReceber>> openReceivables({required String storeId});

  Future<List<ContaPagar>> payables({required String storeId});

  int get remoteQueryCount;
  int get localReadCount;
}

class FinancialDashboardViewData {
  const FinancialDashboardViewData({
    required this.storeId,
    required this.period,
    required this.today,
    required this.read,
    required this.salesAvailable,
    required this.entriesAvailable,
    required this.receivablesAvailable,
    required this.payablesAvailable,
    required this.remoteQueryCount,
    required this.localReadCount,
    required this.remoteWrites,
  });

  final String storeId;
  final FinancialPeriod period;
  final DateTime today;
  final FinancialDashboardRead read;
  final bool salesAvailable;
  final bool entriesAvailable;
  final bool receivablesAvailable;
  final bool payablesAvailable;
  final int remoteQueryCount;
  final int localReadCount;
  final int remoteWrites;
}

class FinancialOverviewLoader {
  const FinancialOverviewLoader();

  Future<FinancialDashboardViewData> load({
    required String storeId,
    required FinancialPeriod period,
    required DateTime today,
    required FinancialPeriodReads reads,
    Set<String> saleTombstones = const {},
    double? estimatedCardFee,
  }) async {
    final sales = await _read(() => reads.sales(storeId: storeId, period: period));
    final entries =
        await _read(() => reads.entries(storeId: storeId, period: period));
    final receivables =
        await _read(() => reads.openReceivables(storeId: storeId));
    final payables = await _read(() => reads.payables(storeId: storeId));

    final sources = FinancialDataSources.scoped(
      storeId: storeId,
      period: period,
      today: today,
      sales: sales.value ?? const [],
      receivables: receivables.value ?? const [],
      entries: entries.value ?? const [],
      payables: payables.value ?? const [],
      saleTombstones: saleTombstones,
      estimatedCardFee: estimatedCardFee,
    );

    return FinancialDashboardViewData(
      storeId: storeId,
      period: period,
      today: today,
      read: FinancialMetricsCalculator.dashboardRead(sources),
      salesAvailable: sales.ok,
      entriesAvailable: entries.ok,
      receivablesAvailable: receivables.ok,
      payablesAvailable: payables.ok,
      remoteQueryCount: reads.remoteQueryCount,
      localReadCount: reads.localReadCount,
      remoteWrites: 0,
    );
  }
}

class _SourceRead<T> {
  const _SourceRead({required this.ok, this.value});

  final bool ok;
  final T? value;
}

Future<_SourceRead<T>> _read<T>(Future<T> Function() load) async {
  try {
    return _SourceRead(ok: true, value: await load());
  } catch (_) {
    return const _SourceRead(ok: false);
  }
}

/// Leituras de período. Cada cartão reutiliza o mesmo resultado.
class FirestoreFinancialPeriodReads implements FinancialPeriodReads {
  FirestoreFinancialPeriodReads({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  int _remote = 0;
  int _local = 0;

  @override
  int get remoteQueryCount => _remote;

  @override
  int get localReadCount => _local;

  @override
  Future<List<Venda>> sales({
    required String storeId,
    required FinancialPeriod period,
  }) async {
    final range = _range(period);
    final query = _db
        .collection('lojas')
        .doc(storeId)
        .collection(FSPaths.estoqueVendasCol)
        .where('data', isGreaterThanOrEqualTo: range.start)
        .where('data', isLessThan: range.endExclusive)
        .orderBy('data');
    final docs = await _pages(query);
    return [
      for (final doc in docs)
        VendasFirestoreService.vendaFromFirestoreMap(doc.data(), doc.id, storeId),
    ];
  }

  @override
  Future<List<LancamentoFinanceiro>> entries({
    required String storeId,
    required FinancialPeriod period,
  }) async {
    final range = _range(period);
    final col = _db
        .collection('lojas')
        .doc(storeId)
        .collection('lancamentos_financeiros');
    final byPayment = await _pages(
      col
          .where('dataPagamento', isGreaterThanOrEqualTo: range.start)
          .where('dataPagamento', isLessThan: range.endExclusive)
          .orderBy('dataPagamento'),
    );
    final byLaunch = await _pages(
      col
          .where('dataLancamento', isGreaterThanOrEqualTo: range.start)
          .where('dataLancamento', isLessThan: range.endExclusive)
          .orderBy('dataLancamento'),
    );
    final seen = <String>{};
    final out = <LancamentoFinanceiro>[];
    for (final doc in [...byPayment, ...byLaunch]) {
      if (!seen.add(doc.id)) continue;
      final parsed = FinanceiroFirestoreService.lancamentoFromFirestoreMap(
        doc.id,
        doc.data(),
        storeId,
      );
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  @override
  Future<List<ContaReceber>> openReceivables({required String storeId}) async {
    final query = _db
        .collection('lojas')
        .doc(storeId)
        .collection(FSPaths.contasReceberCol)
        .where('status', whereIn: ['pendente', 'parcial']);
    final docs = await _pages(query);
    return [
      for (final doc in docs)
        if (ContaReceberFirestoreService.contaFromFirestore(
              doc.id,
              doc.data(),
              storeId,
            )
            case final conta?)
          conta,
    ];
  }

  @override
  Future<List<ContaPagar>> payables({required String storeId}) async {
    final box = await ContaPagarHiveStore.openBox(storeId);
    if (box == null) {
      throw StateError('contas a pagar locais indisponíveis');
    }
    _local++;
    return ContaPagarService.listar(box, storeId).toList(growable: false);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _pages(
    Query<Map<String, dynamic>> query,
  ) async {
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    Query<Map<String, dynamic>> page = query.limit(300);
    while (true) {
      _remote++;
      final snap = await page.get();
      if (snap.docs.isEmpty) break;
      out.addAll(snap.docs);
      if (snap.docs.length < 300) break;
      page = query.limit(300).startAfterDocument(snap.docs.last);
    }
    return out;
  }

  ({Timestamp start, Timestamp endExclusive}) _range(FinancialPeriod period) {
    final start = BrazilBusinessDate.dateOnly(period.periodStart);
    final end = BrazilBusinessDate.dateOnly(period.periodEnd)
        .add(const Duration(days: 1));
    return (start: Timestamp.fromDate(start), endExclusive: Timestamp.fromDate(end));
  }
}
