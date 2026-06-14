// Vínculo venda fiada/mista ↔ conta a receber (cross-device).

import '../core/safe_cast.dart';
import '../models/conta_receber.dart';
import '../models/venda.dart';

String idVendaEstavelParaContaReceber(Venda venda) =>
    (venda.idFirebase ?? '').trim();

double calcularSaldoFiadoVenda({
  required double total,
  required double totalPagoAgora,
}) =>
    (total - totalPagoAgora).clamp(0.0, double.infinity);

double totalPagoAgoraVenda(Venda venda) =>
    venda.pagamentoDinheiro + venda.pagamentoPix + venda.pagamentoCartao;

double valorAReceberDaVenda(Venda venda) => calcularSaldoFiadoVenda(
      total: venda.total,
      totalPagoAgora: totalPagoAgoraVenda(venda),
    );

/// Venda fiada pura, mista (Pix + saldo) ou qualquer saldo a receber aberto.
bool vendaPossuiSaldoAReceber(Venda venda) {
  if (venda.cancelada || venda.estornada) return false;
  return valorAReceberDaVenda(venda) > 0.01;
}

bool contaReceberVinculadaAVenda({
  required ContaReceber conta,
  required String lojaId,
  int? vendaKey,
  String? vendaIdFirebase,
}) {
  if (conta.lojaId.trim() != lojaId.trim()) return false;
  final vk = vendaKey;
  if (vk != null && vk >= 0 && conta.vendaKey == vk) return true;
  final idV = (vendaIdFirebase ?? '').trim();
  if (idV.isEmpty) return false;
  return conta.vendaIdFirebase.trim() == idV;
}

int? vendaHiveKeyOrNull(Venda venda) => hiveKeyOrNull(venda.key);

/// Metadados de fiado extraídos de formasPagamento ou Firestore.
class FiadoVendaMetadata {
  final DateTime? dataVencimento;
  final int quantidadeParcelas;
  final int intervaloDias;
  final double? saldoFiado;

  const FiadoVendaMetadata({
    this.dataVencimento,
    this.quantidadeParcelas = 1,
    this.intervaloDias = 30,
    this.saldoFiado,
  });
}

DateTime? parseVencimentoFiadoFromText(String text) {
  final match = RegExp(
    r'Vencimento:\s*(\d{2})/(\d{2})/(\d{4})',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(3)!),
    int.parse(match.group(2)!),
    int.parse(match.group(1)!),
  );
}

FiadoVendaMetadata parseFiadoMetadataFromFormasPagamento(String text) {
  final raw = text.trim();
  final venc = parseVencimentoFiadoFromText(raw);
  final parcelasMatch = RegExp(
    r'Parcelas?\s+fiado:\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(raw);
  final intervaloMatch = RegExp(
    r'Intervalo:\s*(\d+)\s*dias?',
    caseSensitive: false,
  ).firstMatch(raw);
  final qtd = parcelasMatch != null
      ? int.parse(parcelasMatch.group(1)!).clamp(1, 48)
      : 1;
  final intervalo = intervaloMatch != null
      ? int.parse(intervaloMatch.group(1)!).clamp(1, 120)
      : 30;
  return FiadoVendaMetadata(
    dataVencimento: venc,
    quantidadeParcelas: qtd,
    intervaloDias: intervalo,
  );
}

FiadoVendaMetadata? parseFiadoMetadataFromFirestoreMap(
  Map<String, dynamic> data,
) {
  final saldo = (data['saldoFiado'] as num?)?.toDouble();
  final qtdRaw = data['quantidadeParcelasFiado'];
  final intervaloRaw = data['intervaloParcelasDias'];
  DateTime? venc;
  final vencRaw = data['dataVencimentoFiado'];
  if (vencRaw is DateTime) {
    venc = vencRaw;
  } else if (vencRaw != null && vencRaw.toString().isNotEmpty) {
    try {
      venc = DateTime.parse(vencRaw.toString());
    } catch (_) {}
  }
  venc ??= parseVencimentoFiadoFromText(
    (data['formasPagamento'] ?? '').toString(),
  );
  final qtd = qtdRaw is num ? qtdRaw.toInt().clamp(1, 48) : 1;
  final intervalo =
      intervaloRaw is num ? intervaloRaw.toInt().clamp(1, 120) : 30;
  if (saldo == null && qtd <= 1 && venc == null) {
    return null;
  }
  return FiadoVendaMetadata(
    dataVencimento: venc,
    quantidadeParcelas: qtd,
    intervaloDias: intervalo,
    saldoFiado: saldo,
  );
}

List<double> parcelarValoresContaReceber(double total, int parcelas) {
  final qtd = parcelas.clamp(1, 48);
  final totalCentavos = (total * 100).round();
  final base = totalCentavos ~/ qtd;
  final resto = totalCentavos % qtd;
  return List<double>.generate(
    qtd,
    (i) => (base + (i < resto ? 1 : 0)) / 100.0,
  );
}

/// Monta contas esperadas (1 ou N parcelas) a partir da venda remota/local.
List<ContaReceber> montarContasReceberFromVenda({
  required Venda venda,
  required String lojaId,
  FiadoVendaMetadata? metaRemota,
}) {
  final loja = lojaId.trim();
  if (loja.isEmpty || !vendaPossuiSaldoAReceber(venda)) return [];

  final vendaId = idVendaEstavelParaContaReceber(venda);
  if (vendaId.isEmpty) return [];

  final metaLocal = parseFiadoMetadataFromFormasPagamento(venda.formasPagamento);
  final meta = FiadoVendaMetadata(
    dataVencimento:
        metaRemota?.dataVencimento ?? metaLocal.dataVencimento,
    quantidadeParcelas: (metaRemota?.quantidadeParcelas ?? 0) > 1
        ? metaRemota!.quantidadeParcelas
        : metaLocal.quantidadeParcelas,
    intervaloDias: metaRemota?.intervaloDias ?? metaLocal.intervaloDias,
    saldoFiado: metaRemota?.saldoFiado,
  );

  final saldo = (meta.saldoFiado ?? valorAReceberDaVenda(venda)).clamp(0.0, double.infinity);
  if (saldo <= 0.01) return [];

  final vencBase = meta.dataVencimento ?? venda.data.add(const Duration(days: 30));
  final qtdParcelas = meta.quantidadeParcelas.clamp(1, 48);
  final intervalo = meta.intervaloDias.clamp(1, 120);
  final valores = parcelarValoresContaReceber(saldo, qtdParcelas);
  final vk = hiveKeyOrNull(venda.key);
  final obsBase = venda.observacao.trim();

  final contas = <ContaReceber>[];
  for (var i = 0; i < qtdParcelas; i++) {
    final venc = vencBase.add(Duration(days: i * intervalo));
    contas.add(
      ContaReceber(
        lojaId: loja,
        clienteNome: venda.clienteNome.trim().isEmpty
            ? 'Cliente'
            : venda.clienteNome.trim(),
        valor: valores[i],
        valorOriginal: valores[i],
        dataVencimento: venc,
        dataVenda: venda.data,
        vendaKey: vk != null && vk >= 0 ? vk : -1,
        vendaIdFirebase: vendaId,
        observacao: qtdParcelas > 1
            ? 'Parcela ${i + 1}/$qtdParcelas${obsBase.isNotEmpty ? ' - $obsBase' : ''}'
            : (obsBase.isEmpty ? 'Venda fiada' : obsBase),
        parcelaNumero: i + 1,
        parcelaTotal: qtdParcelas,
      ),
    );
  }
  return contas;
}
