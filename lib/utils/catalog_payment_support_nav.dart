// Navegação interna (root) para a tela de forense do pagamento catálogo MP.
// Sem lógica de negócio: apenas arguments + pushNamed.

import 'package:flutter/material.dart';

/// Mensagem única para feedback de cópia (Snackbar).
const String kCatalogPaymentSupportCopyMessage = 'ID copiado';

/// SnackBar padronizado para qualquer ação de copiar ID neste fluxo.
void showCatalogPaymentSupportCopyFeedback(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(kCatalogPaymentSupportCopyMessage),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
      margin: EdgeInsets.all(12),
    ),
  );
}

/// Abre [CatalogPaymentSupportScreen] via rota nomeada com [arguments] (caminho preferencial interno).
///
/// [autoQuery] envia `autoQuery: 'true'` para a tela disparar uma consulta quando o payload for válido.
void openCatalogPaymentSupport(
  BuildContext context, {
  String? lojaId,
  String? orderId,
  String? externalReference,
  String? paymentId,
  bool autoQuery = false,
}) {
  final m = <String, dynamic>{};
  void p(String k, String? v) {
    final t = v?.trim();
    if (t == null || t.isEmpty) return;
    m[k] = t;
  }

  p('lojaId', lojaId);
  p('orderId', orderId);
  p('externalReference', externalReference);
  p('paymentId', paymentId);
  if (autoQuery) m['autoQuery'] = 'true';

  Navigator.of(context).pushNamed(
    '/catalog_payment_support',
    arguments: m.isEmpty ? null : m,
  );
}
