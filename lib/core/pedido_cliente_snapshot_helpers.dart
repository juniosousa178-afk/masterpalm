// Helpers de snapshot de cliente do pedido (somente leitura).

Map<String, dynamic> pedidoClienteEnderecoMap(Map<String, dynamic> cliente) {
  final raw = cliente['endereco'];
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  return <String, dynamic>{};
}

String pedidoClienteCampo(
  Map<String, dynamic> cliente,
  List<String> keys, {
  String fallback = '',
}) {
  for (final k in keys) {
    final v = cliente[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
  }
  final end = pedidoClienteEnderecoMap(cliente);
  for (final k in keys) {
    final v = end[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
  }
  return fallback;
}

String formatarEnderecoSnapshotCompleto(Map<String, dynamic> cliente) {
  final end = pedidoClienteEnderecoMap(cliente);
  String pick(List<String> keys) {
    for (final k in keys) {
      final v = (end[k] ?? cliente[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  final parts = <String>[
    [
      pick(['rua', 'logradouro', 'endereco', 'street']),
      pick(['numero', 'number', 'n']),
    ].where((e) => e.isNotEmpty).join(', '),
    pick(['complemento', 'complement']),
    pick(['bairro', 'district', 'neighborhood']),
    [
      pick(['cidade', 'city']),
      pick(['estado', 'uf', 'state']),
    ].where((e) => e.isNotEmpty).join(' - '),
    pick(['cep', 'zip']),
    pick(['referencia', 'referência', 'reference']),
  ].where((e) => e.trim().isNotEmpty).toList();

  if (parts.isEmpty) {
    final fmt = (cliente['enderecoFormatado'] ?? '').toString().trim();
    return fmt;
  }
  return parts.join('\n');
}

String googleMapsUrlFromClienteSnapshot(Map<String, dynamic> cliente) {
  final q = formatarEnderecoSnapshotCompleto(cliente)
      .replaceAll('\n', ', ')
      .trim();
  if (q.isEmpty) return '';
  return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}';
}

String whatsappUrlFromTelefone(String telefone) {
  final digits = telefone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  final withCountry =
      digits.startsWith('55') ? digits : '55$digits';
  return 'https://wa.me/$withCountry';
}
