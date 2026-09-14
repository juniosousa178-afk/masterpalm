/// Não cria estoque a partir de cópias legadas do catálogo.
Future<void> migrarParaEstoque(String lojaId) async {
  throw StateError('Migração de estoque pelo app desativada. A fonte canônica precisa de reconciliação autorizada no servidor.');
}
