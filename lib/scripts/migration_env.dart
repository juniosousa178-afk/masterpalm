// Leitura de opções de migração: VM/shell + compile-time (--dart-define).
//
// Na Web não há `dart:io`; usa-se implementação sem [Platform.environment].
// Comando: `--dart-define=MP_MIGRATION_ALL_LOJAS=true` (etc.)

import 'package:master_palm/scripts/migration_env_io.dart'
    if (dart.library.html) 'package:master_palm/scripts/migration_env_web.dart'
    as mig_env;

String migrationEnvString(String key) => mig_env.migrationEnvString(key);

bool migrationEnvFlag(String key) {
  final v = migrationEnvString(key).toLowerCase().trim();
  return v == '1' || v == 'true' || v == 'yes';
}
