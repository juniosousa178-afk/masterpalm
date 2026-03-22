// lib/services/sorteio_numero_service.dart
//
// Usado pelo fluxo APK (`PosPagamentoService`). Pedidos do catálogo pagos via
// Mercado Pago: participação em campanha é registrada no servidor em
// `functions/src/mpWebhookPromo.js` após pagamento aprovado (idempotente).
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

class SorteioNumeroService {
  SorteioNumeroService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // =====================================================================
  // 🔹 1) Gerar número único de 5 dígitos para cada compra
  // =====================================================================
  static String gerarNumeroCliente() {
    final rand = Random();
    final n1 = rand.nextInt(10);
    final n2 = rand.nextInt(10);
    final n3 = rand.nextInt(10);
    final n4 = rand.nextInt(10);
    final n5 = rand.nextInt(10);
    return "$n1$n2$n3$n4$n5"; // ex.: 19473
  }

  // =====================================================================
  // 🔹 2) Registrar número + cliente na campanha ativa
  //     (chamado automaticamente na tela de Vendas)
  //     Retorna true se foi registrado em pelo menos uma campanha ativa
  // =====================================================================
  /// [vendaIdOuPedidoId] — ID da venda/pedido (para cancelarParticipacao e idempotência).
  static Future<bool> registrarNumeroEmCampanhas({
    required String lojaId,
    required String clienteNome,
    String? clienteId,
    required double valorCompra,
    required DateTime dataCompra,
    required String numeroSorte,
    String? vendaIdOuPedidoId,
  }) async {
    final ts = Timestamp.fromDate(dataCompra);
    final now = FieldValue.serverTimestamp();

    final campanhasRef =
        _db.collection('lojas').doc(lojaId).collection('campanhas_sorteio');

    final snap = await campanhasRef
        .where('ativa', isEqualTo: true)
        .where('dataInicio', isLessThanOrEqualTo: ts)
        .where('dataFim', isGreaterThanOrEqualTo: ts)
        .get();

    if (snap.docs.isEmpty) return false;

    bool registrouEmAlguma = false;

    for (final doc in snap.docs) {
      final campanha = doc.data();
      final minimo = (campanha['valorMinimo'] as num?)?.toDouble() ?? 0;

      if (valorCompra < minimo) continue;

      await doc.reference.collection('participantes').add({
        'clienteId': clienteId,
        'clienteNome': clienteNome,
        'nomeCliente': clienteNome, // legado
        'valorCompra': valorCompra,
        'valorPedido': valorCompra,
        'dataCompra': ts,
        'dataParticipacao': now, // schema canônico
        'numeroSorte': numeroSorte,
        'criadoEm': now, // legado
        if (vendaIdOuPedidoId != null) 'pedidoId': vendaIdOuPedidoId,
        if (vendaIdOuPedidoId != null) 'vendaId': vendaIdOuPedidoId,
        'sorteado': false,
        'status': 'valido',
      });

      registrouEmAlguma = true;
    }

    return registrouEmAlguma;
  }

  // =====================================================================
  // 🔹 3) Buscar cliente vencedor a partir de um número sorteado do globo
  // =====================================================================
  static Future<Map<String, dynamic>?> buscarVencedorPorNumero({
    required String lojaId,
    required String campanhaId,
    required String numeroSorte,
  }) async {
    final campanhaRef = _db
        .collection('lojas')
        .doc(lojaId)
        .collection('campanhas_sorteio')
        .doc(campanhaId);

    final snap = await campanhaRef
        .collection('participantes')
        .where('numeroSorte', isEqualTo: numeroSorte)
        .get();

    if (snap.docs.isEmpty) return null;

    // Em regra sempre terá 1, mas se tiver mais, pegamos o primeiro
    final p = snap.docs.first.data();
    return p;
  }

  // =====================================================================
  // 🔹 4) Marcar campanha como sorteada e salvar vencedor
  // =====================================================================
  static Future<void> registrarVencedor({
    required String lojaId,
    required String campanhaId,
    required Map<String, dynamic> vencedor,
    required String numeroSorte,
  }) async {
    await _db
        .collection('lojas')
        .doc(lojaId)
        .collection('campanhas_sorteio')
        .doc(campanhaId)
        .update({
      'status': 'sorteada',
      'sorteadoEm': FieldValue.serverTimestamp(),
      'numeroSorteVencedor': numeroSorte,
      'vencedor': vencedor,
    });
  }
}
