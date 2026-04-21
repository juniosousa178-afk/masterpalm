import 'dart:io' show Platform;

import 'package:master_palm/scripts/migration_env_define.dart';

/// VM / mobile / desktop: `--dart-define` ou [Platform.environment].
String migrationEnvString(String key) {
  final d = migrationEnvStringFromDefine(key);
  if (d.isNotEmpty) return d;
  return Platform.environment[key] ?? '';
}
