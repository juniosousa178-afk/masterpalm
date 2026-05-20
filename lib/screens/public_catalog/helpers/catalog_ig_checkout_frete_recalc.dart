import '../../../core/safe_cast.dart' show asMapDeep;

/// Alinha [entregaPayload] (vinda do HTML) à lista de fretes da loja quando possível.
Map<String, dynamic> catalogIgCheckoutNormalizeEntrega({
  required Map<String, dynamic> entregaPayload,
  required List<Map<String, dynamic>> fretesCatalogo,
}) {
  final nomePayload = (entregaPayload['nome'] ??
          entregaPayload['label'] ??
          '')
      .toString()
      .trim()
      .toLowerCase();
  final tipoPayload =
      (entregaPayload['tipo'] ?? '').toString().trim().toLowerCase();
  final sidPayload =
      (entregaPayload['service_id'] ?? entregaPayload['serviceId'] ?? '')
          .toString()
          .trim();

  int matchIndex = -1;
  for (var i = 0; i < fretesCatalogo.length; i++) {
    final f = fretesCatalogo[i];
    final nome = (f['nome'] ?? f['label'] ?? '').toString().trim().toLowerCase();
    final tipo = (f['tipo'] ?? '').toString().trim().toLowerCase();
    final sid =
        (f['service_id'] ?? f['serviceId'] ?? '').toString().trim();
    if (sidPayload.isNotEmpty && sid.isNotEmpty && sid == sidPayload) {
      matchIndex = i;
      break;
    }
    if (nomePayload.isNotEmpty &&
        nome.isNotEmpty &&
        (nome == nomePayload || nome.contains(nomePayload) || nomePayload.contains(nome))) {
      matchIndex = i;
      break;
    }
    if (tipoPayload.isNotEmpty && tipo.isNotEmpty && tipo == tipoPayload) {
      matchIndex = i;
      break;
    }
  }

  final base = asMapDeep(entregaPayload);
  if (matchIndex < 0) {
    return base;
  }
  final chosen = asMapDeep(fretesCatalogo[matchIndex]);
  final valorCatalogo = chosen['valor'];
  final valorPayload = base['valor'];
  final merged = Map<String, dynamic>.from(chosen);
  merged.addAll(base);
  if (valorCatalogo != null) {
    merged['valor'] = valorCatalogo;
  } else if (valorPayload != null) {
    merged['valor'] = valorPayload;
  }
  merged['_igMatchedFreteIndex'] = matchIndex;
  return merged;
}
