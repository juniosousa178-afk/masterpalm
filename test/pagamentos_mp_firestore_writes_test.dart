import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pagamentos_mp_firestore_writes.dart';

void main() {
  test('manualAccessToken não inclui public_key; remove refresh OAuth', () {
    final m = PagamentosMpFirestoreWrites.manualAccessToken('APP_USR-abc');
    expect(m.keys.toSet(),
        {'access_token', 'token', 'connected', 'refresh_token'});
    expect(m['access_token'], 'APP_USR-abc');
    expect(m['token'], 'APP_USR-abc');
    expect(m['connected'], isTrue);
    expect(m['refresh_token'], isA<FieldValue>());
    expect(m.containsKey('public_key'), isFalse);
    expect(m.containsKey('email'), isFalse);
  });

  test('disconnect remove tokens e marca desconectado', () {
    final m = PagamentosMpFirestoreWrites.disconnect();
    expect(m['connected'], isFalse);
    expect(m['access_token'], isA<FieldValue>());
    expect(m['token'], isA<FieldValue>());
    expect(m['refresh_token'], isA<FieldValue>());
    expect(m['email'], isA<FieldValue>());
    expect(m['user_id'], isA<FieldValue>());
    expect(m['nickname'], isA<FieldValue>());
    expect(m['public_key'], isA<FieldValue>());
    expect(m['access_token_hint'], isA<FieldValue>());
  });

  test('clearIdentityFields só remove campos de exibição', () {
    final m = PagamentosMpFirestoreWrites.clearIdentityFields();
    expect(m.keys.toSet(), {'email', 'user_id', 'nickname'});
    for (final v in m.values) {
      expect(v, isA<FieldValue>());
    }
  });
}
