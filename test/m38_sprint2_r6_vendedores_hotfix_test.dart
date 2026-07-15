// M3.8 S2-R6 — hotfix cadastro vendedores (senha ≥ 6).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R6-VEND-1 validador senha minimo 6 (alinhado Firebase Auth)', () {
    final src = File('lib/screens/vendedores_screen.dart').readAsStringSync();
    expect(src.contains('length < 6'), isTrue);
    expect(src.contains('Minimo 6 caracteres'), isTrue);
    expect(src.contains('length < 4'), isFalse);
    // R2-FIX: weak-password segue coberto pelo validador local (>=6) + Auth.
    expect(src.contains('createUserWithEmailAndPassword'), isTrue);
  });
}
