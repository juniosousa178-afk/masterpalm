import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:master_palm/screens/pre_pedidos/pre_pedido_operacional.dart';

/// Motivo de bloqueio ou elegibilidade para confirmação admin de pré-pedido.
enum PrePedidoConfirmacaoBlockReason {
  eligible,
  alreadyPaidByMercadoPago,
  alreadyConfirmed,
  prePedidoIdMissing,
  documentNotFound,
  inconsistentPaymentState,
}

/// Resultado tipado da elegibilidade de confirmação admin.
class PrePedidoConfirmacaoEligibility {
  const PrePedidoConfirmacaoEligibility._({
    required this.reason,
    required this.data,
  });

  final PrePedidoConfirmacaoBlockReason reason;

  /// Snapshot canônico usado na avaliação (mapa do documento + id), quando existir.
  final Map<String, dynamic>? data;

  bool get isEligible => reason == PrePedidoConfirmacaoBlockReason.eligible;

  String get userMessage {
    switch (reason) {
      case PrePedidoConfirmacaoBlockReason.eligible:
        return '';
      case PrePedidoConfirmacaoBlockReason.alreadyPaidByMercadoPago:
        return 'Este pedido já foi pago e processado pelo Mercado Pago.';
      case PrePedidoConfirmacaoBlockReason.alreadyConfirmed:
        return 'Este pedido já foi confirmado no sistema.';
      case PrePedidoConfirmacaoBlockReason.prePedidoIdMissing:
        return 'Pré-pedido sem identificador.';
      case PrePedidoConfirmacaoBlockReason.documentNotFound:
        return 'Pré-pedido não encontrado.';
      case PrePedidoConfirmacaoBlockReason.inconsistentPaymentState:
        return 'Estado de pagamento inconsistente. Atualize a lista e tente novamente.';
    }
  }

  static PrePedidoConfirmacaoEligibility eligible(Map<String, dynamic> data) {
    return PrePedidoConfirmacaoEligibility._(
      reason: PrePedidoConfirmacaoBlockReason.eligible,
      data: data,
    );
  }

  static PrePedidoConfirmacaoEligibility blocked(
    PrePedidoConfirmacaoBlockReason reason, {
    Map<String, dynamic>? data,
  }) {
    return PrePedidoConfirmacaoEligibility._(
      reason: reason,
      data: data,
    );
  }

  /// Avalia elegibilidade a partir de um mapa (sem I/O).
  static PrePedidoConfirmacaoEligibility evaluateMap(
    Map<String, dynamic>? raw,
  ) {
    if (raw == null || raw.isEmpty) {
      return blocked(PrePedidoConfirmacaoBlockReason.documentNotFound);
    }

    final id = raw['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      return blocked(
        PrePedidoConfirmacaoBlockReason.prePedidoIdMissing,
        data: raw,
      );
    }

    final status = normalizarStatusPrePedido(raw['status']);
    final vendaId = raw['vendaId']?.toString().trim() ?? '';
    if (status == 'confirmado' || vendaId.isNotEmpty) {
      return blocked(
        PrePedidoConfirmacaoBlockReason.alreadyConfirmed,
        data: raw,
      );
    }

    if (_hasInconsistentPaymentState(raw)) {
      return blocked(
        PrePedidoConfirmacaoBlockReason.inconsistentPaymentState,
        data: raw,
      );
    }

    if (isPrePedidoPagamentoGatewayConcluido(raw)) {
      return blocked(
        PrePedidoConfirmacaoBlockReason.alreadyPaidByMercadoPago,
        data: raw,
      );
    }

    return eligible(Map<String, dynamic>.from(raw));
  }
}

bool _hasInconsistentPaymentState(Map<String, dynamic> p) {
  final paidAt = p['paidAt'];
  final paymentId = p['paymentId']?.toString().trim() ?? '';
  final sp =
      (p['statusPagamento'] ?? '').toString().toLowerCase().trim();

  // paidAt sem paymentId em pedido gateway sugere estado parcial/corrompido.
  if (paidAt != null && paymentId.isEmpty) {
    final pagamento = (p['pagamento'] ?? '').toString().toLowerCase();
    if (pagamento.contains('mercado') || pagamento.contains('gateway')) {
      return true;
    }
  }

  // Aprovado sem paidAt nem paymentId.
  if ((sp == 'aprovado' || sp == 'approved') &&
      paidAt == null &&
      paymentId.isEmpty) {
    return true;
  }

  return false;
}

/// Fail-closed: re-lê o documento canônico antes da confirmação admin.
class PrePedidoConfirmacaoEligibilityService {
  PrePedidoConfirmacaoEligibilityService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<PrePedidoConfirmacaoEligibility> loadAndEvaluate({
    required String lojaId,
    required String prePedidoId,
  }) async {
    final id = prePedidoId.trim();
    if (id.isEmpty) {
      return PrePedidoConfirmacaoEligibility.blocked(
        PrePedidoConfirmacaoBlockReason.prePedidoIdMissing,
      );
    }

    final snap = await _firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('pre_pedidos')
        .doc(id)
        .get();

    if (!snap.exists) {
      return PrePedidoConfirmacaoEligibility.blocked(
        PrePedidoConfirmacaoBlockReason.documentNotFound,
      );
    }

    final data = <String, dynamic>{
      'id': snap.id,
      ...?snap.data(),
    };
    return PrePedidoConfirmacaoEligibility.evaluateMap(data);
  }
}

class PrePedidoConfirmacaoBloqueadaException implements Exception {
  PrePedidoConfirmacaoBloqueadaException(this.eligibility);

  final PrePedidoConfirmacaoEligibility eligibility;

  @override
  String toString() =>
      'PrePedidoConfirmacaoBloqueadaException(${eligibility.reason})';
}
