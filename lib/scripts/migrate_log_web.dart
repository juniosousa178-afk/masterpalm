import 'package:flutter/foundation.dart' show debugPrint;

void migrateLogOut(String message) => debugPrint(message);

void migrateLogErr(String message) => debugPrint('[migração] $message');
