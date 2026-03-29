// Evita loop: sync Firestore → Hive dispara box.watch do auto-sync.
// Ficheiro isolado para [ProdutosFirestoreService] e [ProdutoAutoSyncService]
// sem import circular.
class ProdutoRemoteSyncGuard {
  ProdutoRemoteSyncGuard._();

  static bool applyingRemoteToHive = false;
}
