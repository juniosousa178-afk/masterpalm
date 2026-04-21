import 'package:master_palm/scripts/migration_env_define.dart';

/// Web: sem `dart:io` — só `--dart-define` (PowerShell não alimenta o browser).
String migrationEnvString(String key) {
  final d = migrationEnvStringFromDefine(key);
  if (d.isNotEmpty) return d;
  return '';
}
