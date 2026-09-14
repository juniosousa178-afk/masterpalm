/// Ferramenta legada aposentada: copiar catálogo não cria estoque canônico.
/// Migração exige manutenção, inventário e plano revisado no servidor.
class MigrateCollectionsService {
  Future<void> migrateAll() async {
    throw StateError('Migração de coleções pelo app desativada. Use o processo autorizado de migração do protocolo de estoque.');
  }
}
