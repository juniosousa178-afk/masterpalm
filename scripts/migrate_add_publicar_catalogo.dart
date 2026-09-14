// Ferramenta aposentada: flags de publicação são alteradas pelo backend derivador.
Future<void> main() async {
  throw StateError('Migração direta de publicação desativada. Use o protocolo de estoque/catálogo no servidor.');
}
