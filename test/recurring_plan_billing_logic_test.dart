import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/recurring_plan_billing_logic.dart';

void main() {
  group('parseRecurringAllowlist', () {
    test('CSV com vírgula, espaços e e-mail com maiúsculas', () {
      final s = parseRecurringAllowlist(
        'H3be6ett8NZBjzh0nJa35tligDZ2, email@Teste.com ',
      );
      expect(
        s,
        contains('H3be6ett8NZBjzh0nJa35tligDZ2'),
      );
      expect(s, contains('email@teste.com'));
    });

    test('ignores entradas vazias', () {
      final s = parseRecurringAllowlist('a,,  b@X.COM');
      expect(s, {'a', 'b@x.com'});
    });
  });

  group('isUserAllowedForRecurringBilling', () {
    const uidT = 'H3be6ett8NZBjzh0nJa35tligDZ2';
    const allow =
        'H3be6ett8NZBjzh0nJa35tligDZ2, email@teste.com';
    final allowset = parseRecurringAllowlist(allow);

    test('global true ativa', () {
      String? r;
      final ok = isUserAllowedForRecurringBilling(
        globalFromRemoteConfig: true,
        allowlist: const {},
        uid: 'any',
        email: 'x@y.com',
        onLog: (x) => r = x,
      );
      expect(ok, isTrue);
      expect(r, 'global_remote_config');
    });

    test('allowlist UID ativa', () {
      String? r;
      final ok = isUserAllowedForRecurringBilling(
        globalFromRemoteConfig: false,
        allowlist: allowset,
        uid: uidT,
        email: 'outro@mail.com',
        onLog: (x) => r = x,
      );
      expect(ok, isTrue);
      expect(r, 'allowlist_uid');
    });

    test('allowlist e-mail (normalizado) ativa', () {
      String? r;
      final ok = isUserAllowedForRecurringBilling(
        globalFromRemoteConfig: false,
        allowlist: allowset,
        uid: 'nada',
        email: '  Email@TESTE.com ',
        onLog: (x) => r = x,
      );
      expect(ok, isTrue);
      expect(r, 'allowlist_email');
    });

    test('espaços e maiúsculas no CSV não impedem e-mail', () {
      String? r;
      final s = parseRecurringAllowlist(' , Email@Teste.COM , otherUid ');
      final ok = isUserAllowedForRecurringBilling(
        globalFromRemoteConfig: false,
        allowlist: s,
        uid: 'nãoEstáNaLista',
        email: 'email@teste.com',
        onLog: (x) => r = x,
      );
      expect(ok, isTrue);
      expect(r, 'allowlist_email');
    });

    test('sem global e fora da allowlist retorna false', () {
      String? r;
      final ok = isUserAllowedForRecurringBilling(
        globalFromRemoteConfig: false,
        allowlist: allowset,
        uid: 'nope',
        email: 'a@b.c',
        onLog: (x) => r = x,
      );
      expect(ok, isFalse);
      expect(r, isNull);
    });
  });
}
