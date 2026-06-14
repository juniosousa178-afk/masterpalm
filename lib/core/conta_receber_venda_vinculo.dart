// Vínculo venda fiada ↔ conta a receber (cross-device).

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
