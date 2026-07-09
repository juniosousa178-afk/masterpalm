// M3.7 — Rules campanhas_sorteio create (belongsToStore).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('firestore.rules permite create campanhas_sorteio para belongsToStore', () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules, contains('match /campanhas_sorteio/{campanhaId}'));
    expect(
      rules,
      contains(
        'allow create, update, delete: if belongsToStore(lojaId);',
      ),
    );
  });
}
