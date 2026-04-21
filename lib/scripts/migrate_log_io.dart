import 'dart:io' show stderr, stdout;

void migrateLogOut(String message) => stdout.writeln(message);

void migrateLogErr(String message) => stderr.writeln(message);
