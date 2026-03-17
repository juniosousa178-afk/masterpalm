// lib/services/payments_config_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/payments_config.dart';

/// Service para carregar/salvar a CONFIGURAÇÃO PUBLICADA de pagamentos
/// usada pelo app (checkout, etc).
///
/// Path:
///   /lojas/{lojaId}/config/payments
///
/// A tela de Loja Config trabalha no RASCUNHO em:
///   /lojas/{lojaId}/draft_config/pagamentos
/// e o fluxo de "Publicar" deve copiar do draft para config/payments
/// usando PaymentsConfig / Cloud Functions / etc.
class PaymentsConfigService {
  PaymentsConfigService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _doc(String lojaId) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection('config')
        .doc('payments');
  }

  /// Carrega config de pagamentos da loja (PUBLICADA).
  static Future<PaymentsConfig> load(String lojaId) async {
    final snap = await _doc(lojaId).get();
    if (!snap.exists) {
      return PaymentsConfig.empty();
    }
    final data = snap.data() ?? {};
    return PaymentsConfig.fromMap(data);
  }

  /// Salva config de pagamentos da loja (PUBLICADA).
  static Future<void> save(String lojaId, PaymentsConfig cfg) async {
    await _doc(lojaId).set(
      cfg.toMap(),
      SetOptions(merge: true),
    );
  }
}
