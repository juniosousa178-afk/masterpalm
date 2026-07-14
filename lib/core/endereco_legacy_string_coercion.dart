// Coerção segura de endereço Firestore (Map estruturado ou String legado) → String?.
// Usado por modelos Hive/admin que ainda tipam `endereco` como String?.

/// Converte `endereco` legado/híbrido para [String?] sem cast directo.
///
/// Política:
/// 1. [enderecoRaw] String → trim; null se vazio
/// 2. [enderecoFormatado] não vazio → preferido quando raw não é String útil
/// 3. [enderecoRaw] Map → monta linha (rua, número, complemento, bairro, cidade, UF, CEP)
/// 4. Outros tipos → toString().trim(); null se vazio
String? coerceEnderecoLegacyString({
  required dynamic enderecoRaw,
  dynamic enderecoFormatado,
}) {
  if (enderecoRaw is String) {
    final s = enderecoRaw.trim();
    return s.isEmpty ? null : s;
  }

  final fmt = _trimmedNonEmpty(enderecoFormatado);
  if (fmt != null) return fmt;

  if (enderecoRaw is Map) {
    return _linhaFromEnderecoMap(enderecoRaw);
  }

  if (enderecoRaw == null) return null;
  return _trimmedNonEmpty(enderecoRaw);
}

String? _trimmedNonEmpty(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    return s;
  }
  // Evita "Instance of ..." / valores não escalares.
  if (v is Map || v is List) return null;
  final s = v.toString().trim();
  if (s.isEmpty || s.toLowerCase() == 'null') return null;
  return s;
}

String? _pickMapField(Map map, List<String> keys) {
  for (final k in keys) {
    final v = map[k];
    final s = _trimmedNonEmpty(v);
    if (s != null) return s;
  }
  return null;
}

String? _linhaFromEnderecoMap(Map map) {
  final rua = _pickMapField(map, ['rua', 'logradouro', 'endereco', 'street']);
  final numero = _pickMapField(map, ['numero', 'number', 'n']);
  final complemento = _pickMapField(map, ['complemento', 'complement']);
  final bairro = _pickMapField(map, ['bairro', 'district', 'neighborhood']);
  final cidade = _pickMapField(map, ['cidade', 'city']);
  final estado = _pickMapField(map, ['estado', 'uf', 'state']);
  final cep = _pickMapField(map, ['cep', 'zip']);

  final parts = <String>[];

  final linha1 = [
    if (rua != null) rua,
    if (numero != null) numero,
  ].join(', ');
  if (linha1.isNotEmpty) parts.add(linha1);

  if (complemento != null) parts.add(complemento);
  if (bairro != null) parts.add(bairro);

  final cidadeUf = [
    if (cidade != null) cidade,
    if (estado != null) estado,
  ].join(' - ');
  if (cidadeUf.isNotEmpty) parts.add(cidadeUf);

  if (cep != null) parts.add(cep);

  if (parts.isEmpty) return null;
  return parts.join(', ');
}
