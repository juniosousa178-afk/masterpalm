// Parte comum: valores vindos só de `--dart-define` (compile-time).

String migrationEnvStringFromDefine(String key) {
  switch (key) {
    case 'MP_MIGRATION_ALL_LOJAS':
      const d = String.fromEnvironment('MP_MIGRATION_ALL_LOJAS', defaultValue: '');
      return d;
    case 'MP_MIGRATION_LOJA_ID':
      const d = String.fromEnvironment('MP_MIGRATION_LOJA_ID', defaultValue: '');
      return d;
    case 'MP_MIGRATION_COMMIT':
      const d = String.fromEnvironment('MP_MIGRATION_COMMIT', defaultValue: '');
      return d;
    case 'MP_MIGRATION_EMAIL':
      const d = String.fromEnvironment('MP_MIGRATION_EMAIL', defaultValue: '');
      return d;
    case 'MP_MIGRATION_PASSWORD':
      const d = String.fromEnvironment('MP_MIGRATION_PASSWORD', defaultValue: '');
      return d;
    case 'MP_MIGRATION_INCLUDE_DRAFT':
      const d =
          String.fromEnvironment('MP_MIGRATION_INCLUDE_DRAFT', defaultValue: '');
      return d;
    case 'MP_MIGRATION_LIMIT':
      const d = String.fromEnvironment('MP_MIGRATION_LIMIT', defaultValue: '');
      return d;
    default:
      return '';
  }
}
