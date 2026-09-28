import '../../models/fechamento_mensal.dart';
import '../../models/lancamento_financeiro.dart';
import '../../models/venda.dart';
import 'brazil_business_date.dart';
import 'financial_month.dart';

/// Origem interna do número exibido. Não entra no texto da loja.
enum FinancialHistoricalSource {
  liveRemote,
  monthlyClosure,
  remoteRaw,
  localOnly,
  mergedLocalRemote,
  unavailable,
}

/// Quantidade fixa de leituras. Não cresce com o número de vendas.
abstract final class FinancialHistoricalQueryPlan {
  static const historicalMonthMetadataQueryCount = 6;
  static const selectedMonthRemoteQueryCount = 2;
  static const selectedMonthClosureReadCount = 1;
  static const nPlusOneDetected = false;
  static const remoteLaunchToHiveAutoWrite = false;
  static const remoteClosureToHiveAutoWrite = false;
  static const localHiveWritesFromRead = 0;
}

class FinancialLaunchMergeResult {
  const FinancialLaunchMergeResult({
    required this.visible,
    required this.remainingDuplicateCount,
    required this.conflictIds,
    required this.silentOverwrite,
    required this.crossTenantDropped,
    required this.localOnlyCount,
  });

  final List<LancamentoFinanceiro> visible;
  final int remainingDuplicateCount;
  final List<String> conflictIds;
  final bool silentOverwrite;
  final int crossTenantDropped;
  final int localOnlyCount;
}

class FinancialMonthReport {
  const FinancialMonthReport({
    required this.available,
    required this.vendaTotal,
    required this.source,
    required this.doubleCounted,
    required this.currentMonthUsesLive,
    required this.knownZero,
  });

  const FinancialMonthReport.unavailable()
      : available = false,
        vendaTotal = null,
        source = FinancialHistoricalSource.unavailable,
        doubleCounted = false,
        currentMonthUsesLive = false,
        knownZero = false;

  final bool available;
  final double? vendaTotal;
  final FinancialHistoricalSource source;
  final bool doubleCounted;
  final bool currentMonthUsesLive;
  final bool knownZero;
}

class FinancialYearVisibility {
  const FinancialYearVisibility({
    required this.available,
    required this.vendaTotal,
    required this.taxasTotal,
    required this.custoTotal,
    required this.lucroTotal,
    required this.totalDinheiro,
    required this.totalPix,
    required this.totalCartao,
    required this.historyVisible,
    required this.currentMonthUsesLiveData,
    required this.doubleCounted,
    required this.needsSingleRawFallback,
    required this.source,
  });

  const FinancialYearVisibility.unavailable()
      : available = false,
        vendaTotal = null,
        taxasTotal = null,
        custoTotal = null,
        lucroTotal = null,
        totalDinheiro = null,
        totalPix = null,
        totalCartao = null,
        historyVisible = false,
        currentMonthUsesLiveData = false,
        doubleCounted = false,
        needsSingleRawFallback = false,
        source = FinancialHistoricalSource.unavailable;

  final bool available;
  final double? vendaTotal;
  final double? taxasTotal;
  final double? custoTotal;
  final double? lucroTotal;
  final double? totalDinheiro;
  final double? totalPix;
  final double? totalCartao;
  final bool historyVisible;
  final bool currentMonthUsesLiveData;
  final bool doubleCounted;
  final bool needsSingleRawFallback;
  final FinancialHistoricalSource source;
}

class FinancialClosureTotals {
  const FinancialClosureTotals({
    required this.vendaTotal,
    required this.taxasTotal,
    required this.custoTotal,
    required this.lucroTotal,
    required this.totalDinheiro,
    required this.totalPix,
    required this.totalCartao,
  });

  final double vendaTotal;
  final double taxasTotal;
  final double custoTotal;
  final double lucroTotal;
  final double totalDinheiro;
  final double totalPix;
  final double totalCartao;

  FinancialClosureTotals operator +(FinancialClosureTotals other) {
    return FinancialClosureTotals(
      vendaTotal: vendaTotal + other.vendaTotal,
      taxasTotal: taxasTotal + other.taxasTotal,
      custoTotal: custoTotal + other.custoTotal,
      lucroTotal: lucroTotal + other.lucroTotal,
      totalDinheiro: totalDinheiro + other.totalDinheiro,
      totalPix: totalPix + other.totalPix,
      totalCartao: totalCartao + other.totalCartao,
    );
  }
}

bool launchesMateriallyDiffer(
  LancamentoFinanceiro a,
  LancamentoFinanceiro b,
) {
  if (a.lojaId.trim() != b.lojaId.trim()) return true;
  if ((a.valor - b.valor).abs() > 0.001) return true;
  if (a.tipo.trim() != b.tipo.trim()) return true;
  if (a.categoria.trim() != b.categoria.trim()) return true;
  if (a.status.trim().toLowerCase() != b.status.trim().toLowerCase()) {
    return true;
  }
  if (a.competenciaMes != b.competenciaMes) return true;
  if (a.competenciaAno != b.competenciaAno) return true;
  if (!_sameInstant(a.dataLancamento, b.dataLancamento)) return true;
  if (!_sameInstant(a.dataPagamento, b.dataPagamento)) return true;
  return false;
}

bool _sameInstant(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.toUtc().millisecondsSinceEpoch == b.toUtc().millisecondsSinceEpoch;
}

FinancialLaunchMergeResult mergeLaunchesForDisplay({
  required String storeId,
  required FinancialMonth month,
  required List<LancamentoFinanceiro> local,
  required List<LancamentoFinanceiro> remote,
}) {
  final id = storeId.trim();
  var dropped = 0;
  final localById = <String, LancamentoFinanceiro>{};
  for (final item in local) {
    if (item.lojaId.trim() != id) {
      dropped++;
      continue;
    }
    if (!month.containsInstant(item.dataEfetivaPagamentoOuLancamento)) {
      continue;
    }
    localById[item.id] = item;
  }
  final remoteById = <String, LancamentoFinanceiro>{};
  for (final item in remote) {
    if (item.lojaId.trim() != id) {
      dropped++;
      continue;
    }
    if (!month.containsInstant(item.dataEfetivaPagamentoOuLancamento)) {
      continue;
    }
    remoteById[item.id] = item;
  }

  final conflicts = <String>[];
  final visible = <LancamentoFinanceiro>[];
  final ids = <String>{...localById.keys, ...remoteById.keys}.toList()
    ..sort();
  var localOnly = 0;
  for (final launchId in ids) {
    final left = localById[launchId];
    final right = remoteById[launchId];
    if (left != null && right != null) {
      if (launchesMateriallyDiffer(left, right)) {
        conflicts.add(launchId);
      }
      visible.add(left);
    } else if (left != null) {
      localOnly++;
      visible.add(left);
    } else if (right != null) {
      visible.add(right);
    }
  }
  visible.sort(
    (a, b) => b.dataEfetivaPagamentoOuLancamento
        .compareTo(a.dataEfetivaPagamentoOuLancamento),
  );
  final seen = <String>{};
  var remaining = 0;
  for (final item in visible) {
    if (!seen.add(item.id)) remaining++;
  }
  return FinancialLaunchMergeResult(
    visible: visible,
    remainingDuplicateCount: remaining,
    conflictIds: conflicts,
    silentOverwrite: false,
    crossTenantDropped: dropped,
    localOnlyCount: localOnly,
  );
}

FinancialMonth? monthFromClosureDocumentId(String documentId, String storeId) {
  final suffix = '-${storeId.trim()}';
  if (!documentId.endsWith(suffix)) return null;
  final prefix = documentId.substring(0, documentId.length - suffix.length);
  if (prefix.length != 7 || prefix[4] != '-') return null;
  final year = int.tryParse(prefix.substring(0, 4));
  final month = int.tryParse(prefix.substring(5, 7));
  if (year == null || month == null || month < 1 || month > 12) return null;
  return FinancialMonth(year, month);
}

String closureDocumentId(String storeId, FinancialMonth month) {
  final mm = month.month.toString().padLeft(2, '0');
  return '${month.year}-$mm-${storeId.trim()}';
}

FinancialMonthReport resolveMonthReport({
  required FinancialMonth month,
  required DateTime now,
  required String storeId,
  required bool remoteFailed,
  FechamentoMensal? closure,
  double? rawVendaTotal,
}) {
  if (remoteFailed) return const FinancialMonthReport.unavailable();
  final current = FinancialMonth.fromClock(now);
  if (month == current) {
    final raw = rawVendaTotal ?? 0;
    return FinancialMonthReport(
      available: true,
      vendaTotal: raw,
      source: FinancialHistoricalSource.liveRemote,
      doubleCounted: false,
      currentMonthUsesLive: true,
      knownZero: raw == 0,
    );
  }
  final past = month.orderKey < current.orderKey;
  final closureOk = closure != null &&
      closure.lojaId.trim() == storeId.trim() &&
      closure.ano == month.year &&
      closure.mes == month.month;
  if (past && closureOk) {
    return FinancialMonthReport(
      available: true,
      vendaTotal: closure.vendaTotal,
      source: FinancialHistoricalSource.monthlyClosure,
      doubleCounted: false,
      currentMonthUsesLive: false,
      knownZero: false,
    );
  }
  final raw = rawVendaTotal ?? 0;
  return FinancialMonthReport(
    available: true,
    vendaTotal: raw,
    source: FinancialHistoricalSource.remoteRaw,
    doubleCounted: false,
    currentMonthUsesLive: false,
    knownZero: raw == 0,
  );
}

FinancialClosureTotals totalsFromClosure(FechamentoMensal closure) {
  return FinancialClosureTotals(
    vendaTotal: closure.vendaTotal,
    taxasTotal: closure.taxasTotal,
    custoTotal: closure.custoTotal,
    lucroTotal: closure.lucroTotal,
    totalDinheiro: closure.totalDinheiro,
    totalPix: closure.totalPix,
    totalCartao: closure.totalCartao,
  );
}

/// Soma fechamentos dos meses passados e o ao vivo só no mês corrente.
/// Se faltar um fechamento, não devolve soma parcial: pede uma única leitura bruta.
FinancialYearVisibility resolveYearVisibility({
  required int year,
  required DateTime now,
  required FinancialMonth earliest,
  required List<FechamentoMensal> closures,
  required String storeId,
  required FinancialClosureTotals currentMonthLive,
  required bool remoteFailed,
}) {
  if (remoteFailed) return const FinancialYearVisibility.unavailable();
  final current = FinancialMonth.fromClock(now);
  if (year > current.year) {
    return const FinancialYearVisibility(
      available: true,
      vendaTotal: 0,
      taxasTotal: 0,
      custoTotal: 0,
      lucroTotal: 0,
      totalDinheiro: 0,
      totalPix: 0,
      totalCartao: 0,
      historyVisible: false,
      currentMonthUsesLiveData: false,
      doubleCounted: false,
      needsSingleRawFallback: false,
      source: FinancialHistoricalSource.remoteRaw,
    );
  }

  final lastPast = year < current.year
      ? FinancialMonth(year, 12)
      : (current.month == 1 ? null : FinancialMonth(year, current.month - 1));
  final start = FinancialMonth(year, 1).orderKey < earliest.orderKey
      ? earliest
      : FinancialMonth(year, 1);
  if (start.year != year) {
    return const FinancialYearVisibility(
      available: true,
      vendaTotal: 0,
      taxasTotal: 0,
      custoTotal: 0,
      lucroTotal: 0,
      totalDinheiro: 0,
      totalPix: 0,
      totalCartao: 0,
      historyVisible: false,
      currentMonthUsesLiveData: false,
      doubleCounted: false,
      needsSingleRawFallback: false,
      source: FinancialHistoricalSource.remoteRaw,
    );
  }

  var past = const FinancialClosureTotals(
    vendaTotal: 0,
    taxasTotal: 0,
    custoTotal: 0,
    lucroTotal: 0,
    totalDinheiro: 0,
    totalPix: 0,
    totalCartao: 0,
  );
  if (lastPast != null && start.orderKey <= lastPast.orderKey) {
    var cursor = start;
    while (true) {
      FechamentoMensal? found;
      for (final closure in closures) {
        if (closure.lojaId.trim() != storeId.trim()) continue;
        if (closure.ano == cursor.year && closure.mes == cursor.month) {
          found = closure;
          break;
        }
      }
      if (found == null) {
        return const FinancialYearVisibility(
          available: false,
          vendaTotal: null,
          taxasTotal: null,
          custoTotal: null,
          lucroTotal: null,
          totalDinheiro: null,
          totalPix: null,
          totalCartao: null,
          historyVisible: false,
          currentMonthUsesLiveData: false,
          doubleCounted: false,
          needsSingleRawFallback: true,
          source: FinancialHistoricalSource.remoteRaw,
        );
      }
      past += totalsFromClosure(found);
      if (cursor == lastPast) break;
      cursor = cursor.month == 12
          ? FinancialMonth(cursor.year + 1, 1)
          : FinancialMonth(cursor.year, cursor.month + 1);
    }
  }

  final includeLive = year == current.year;
  final combined = includeLive
      ? FinancialClosureTotals(
          vendaTotal: past.vendaTotal + currentMonthLive.vendaTotal,
          taxasTotal: past.taxasTotal + currentMonthLive.taxasTotal,
          custoTotal: past.custoTotal + currentMonthLive.custoTotal,
          lucroTotal: past.lucroTotal + currentMonthLive.lucroTotal,
          totalDinheiro: past.totalDinheiro + currentMonthLive.totalDinheiro,
          totalPix: past.totalPix + currentMonthLive.totalPix,
          totalCartao: past.totalCartao + currentMonthLive.totalCartao,
        )
      : past;
  return FinancialYearVisibility(
    available: true,
    vendaTotal: combined.vendaTotal,
    taxasTotal: combined.taxasTotal,
    custoTotal: combined.custoTotal,
    lucroTotal: combined.lucroTotal,
    totalDinheiro: combined.totalDinheiro,
    totalPix: combined.totalPix,
    totalCartao: combined.totalCartao,
    historyVisible: lastPast != null || includeLive,
    currentMonthUsesLiveData: includeLive,
    doubleCounted: false,
    needsSingleRawFallback: false,
    source: includeLive
        ? FinancialHistoricalSource.mergedLocalRemote
        : FinancialHistoricalSource.monthlyClosure,
  );
}

String? vendaCanonicalId(Venda venda) {
  final remote = (venda.idFirebase ?? '').trim();
  if (remote.isNotEmpty) return remote;
  if (venda.isInBox && venda.key != null) return 'hive:${venda.key}';
  return null;
}

class VendaMergeResult {
  const VendaMergeResult({
    required this.visible,
    required this.crossTenantDropped,
    required this.remainingDuplicateCount,
  });

  final List<Venda> visible;
  final int crossTenantDropped;
  final int remainingDuplicateCount;
}

VendaMergeResult mergeVendasForDisplay({
  required String storeId,
  required List<Venda> local,
  required List<Venda> remote,
}) {
  final id = storeId.trim();
  var dropped = 0;
  final visible = <Venda>[];
  final seen = <String>{};
  for (final venda in <Venda>[...local, ...remote]) {
    final loja = (venda.lojaId ?? '').trim();
    if (loja.isNotEmpty && loja != id) {
      dropped++;
      continue;
    }
    final key = vendaCanonicalId(venda);
    if (key != null && !seen.add(key)) continue;
    visible.add(venda);
  }
  return VendaMergeResult(
    visible: visible,
    crossTenantDropped: dropped,
    remainingDuplicateCount: 0,
  );
}

bool launchBelongsToBusinessMonth(
  LancamentoFinanceiro launch,
  FinancialMonth month,
) {
  return month.containsInstant(launch.dataEfetivaPagamentoOuLancamento);
}

DateTime businessDayFromUtc(DateTime utc) {
  final day = BrazilBusinessDate.dateOnly(utc.toUtc());
  return DateTime(day.year, day.month, day.day, 12);
}
