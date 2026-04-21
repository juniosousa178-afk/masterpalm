// Este script usa `cloud_firestore` (Flutter) e NÃO pode ser executado com `dart run`
// do SDK isolado — falta `dart:ui`.
//
// Use na raiz do projeto:
//
//   fvm flutter test test/migrate_produto_storage_urls_test.dart
//
// Variáveis de ambiente: ver cabeçalho de test/migrate_produto_storage_urls_test.dart
//
// Resumo rápido:
//   Todas as lojas (dry-run):  MP_MIGRATION_ALL_LOJAS=true
//   Uma loja:                  MP_MIGRATION_LOJA_ID=<id>
//   Gravar:                    MP_MIGRATION_COMMIT=true + MP_MIGRATION_EMAIL + MP_MIGRATION_PASSWORD

import 'dart:io';

void main() {
  stderr.writeln(
    'Este ficheiro não deve ser executado com `dart run`.\n\n'
    'Corra a migração com Flutter:\n'
    '  fvm flutter test test/migrate_produto_storage_urls_test.dart\n\n'
    'Defina MP_MIGRATION_ALL_LOJAS=true (todas as lojas) ou MP_MIGRATION_LOJA_ID=<id>.\n'
    'Ver comentários no ficheiro de teste para MP_MIGRATION_COMMIT, INCLUDE_DRAFT, etc.\n',
  );
  exitCode = 64;
}
