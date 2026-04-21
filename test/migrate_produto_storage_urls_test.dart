// Migração de URLs Firebase Storage em produtos (imageUrl, imagem_principal, imagens).
//
// NÃO use `dart run` — o plugin cloud_firestore depende do Flutter (`dart:ui`).
// Execute na raiz do projeto:
//
//   fvm flutter test test/migrate_produto_storage_urls_test.dart
//
// Se aparecer channel-error do Firebase no teste, use um alvo com embedder:
//
//   fvm flutter run -t lib/migrate_produto_storage_urls_entry.dart -d windows
//
// Variáveis de ambiente (PowerShell):
//
//   Uma loja:
//     $env:MP_MIGRATION_LOJA_ID="idFirestore"
//
//   Todas as lojas:
//     $env:MP_MIGRATION_ALL_LOJAS="true"
//
//   Opcional:
//     $env:MP_MIGRATION_INCLUDE_DRAFT="true"   # inclui draft_produtos
//     $env:MP_MIGRATION_COMMIT="true"          # grava (requer admin)
//     $env:MP_MIGRATION_LIMIT="50"             # max docs por coleção por loja (testes)
//     $env:MP_MIGRATION_EMAIL / $env:MP_MIGRATION_PASSWORD  # obrigatórios se COMMIT=true
//
// Exemplo dry-run em todas as lojas (teste VM / desktop):
//   $env:MP_MIGRATION_ALL_LOJAS="true"; fvm flutter test test/migrate_produto_storage_urls_test.dart
//
// Chrome / Web: variáveis do PowerShell NÃO entram no browser — use --dart-define, ex.:
//   fvm flutter run -t lib/migrate_produto_storage_urls_entry.dart -d chrome `
//     --dart-define=MP_MIGRATION_ALL_LOJAS=true

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/scripts/migrate_produto_storage_urls_runner.dart';

void main() {
  // Obrigatório antes de Firebase.initializeApp (plugins usam platform channels).
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'migrate_produto_storage_urls',
    () async {
      try {
        await runMigrateProdutoStorageUrlsFromEnvironment();
      } on StateError catch (e) {
        fail(e.message);
      }
    },
    timeout: Timeout.none,
  );
}
