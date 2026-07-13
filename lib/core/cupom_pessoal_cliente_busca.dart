// Busca local/case-insensitive de clientes para vincular cupom pessoal.
// Espelha o comportamento do PDV (Hive contains), não o prefixo Firestore.

/// Semântica quebrada usada antes: prefixo Firestore com query já lowercased
/// contra `nome` armazenado em Title Case.
bool cupomPessoalFirestorePrefixMatchBroken({
  required String nomeArmazenado,
  required String queryDigitada,
}) {
  final queryLower = queryDigitada.trim().toLowerCase();
  if (queryLower.length < 2) return false;
  // Firestore string range é case-sensitive; nomes em Title Case ficam
  // lexicograficamente antes de "maria..." e nunca entram no range.
  return nomeArmazenado.compareTo(queryLower) >= 0 &&
      nomeArmazenado.compareTo('$queryLower\uf8ff') <= 0;
}

/// Filtro canônico para seleção de cliente no cupom pessoal (case-insensitive).
List<Map<String, dynamic>> filtrarClientesCupomPessoal({
  required List<Map<String, dynamic>> clientes,
  required String query,
  int limit = 10,
}) {
  final q = query.trim().toLowerCase();
  if (q.length < 2) return const [];

  final out = <Map<String, dynamic>>[];
  for (final c in clientes) {
    final nome = (c['nome'] ?? '').toString().toLowerCase();
    final email = (c['email'] ?? '').toString().toLowerCase();
    final telefone = (c['telefone'] ?? '').toString().toLowerCase();
    if (nome.contains(q) || email.contains(q) || telefone.contains(q)) {
      out.add(c);
      if (out.length >= limit) break;
    }
  }
  return out;
}

/// Normaliza mapa de cliente para gravação do cupom (id estável + e-mail).
Map<String, dynamic> normalizarClienteSelecionadoCupom(
  Map<String, dynamic> cliente,
) {
  final id = (cliente['id'] ??
          cliente['clienteId'] ??
          cliente['idFirebase'] ??
          '')
      .toString()
      .trim();
  final email = (cliente['email'] ?? '').toString().trim().toLowerCase();
  return {
    ...cliente,
    if (id.isNotEmpty) 'id': id,
    if (id.isNotEmpty) 'clienteId': id,
    if (email.isNotEmpty) 'email': email,
  };
}
