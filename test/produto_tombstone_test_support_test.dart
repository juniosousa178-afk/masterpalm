// Garante que helpers de seed de tombstone não existem em lib/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/ não contém seedProdutoTombstoneLocalForTests', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue);
    final hits = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) => RegExp(
            r'seedProdutoTombstoneLocalForTests|seed.*Tombstone.*ForTests',
          ).hasMatch(File(f.path).readAsStringSync()),
        )
        .map((f) => f.path)
        .toList();
    expect(hits, isEmpty, reason: 'Helpers de seed em produção: $hits');
  });
}
