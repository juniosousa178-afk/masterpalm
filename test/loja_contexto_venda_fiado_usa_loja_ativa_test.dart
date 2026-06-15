// Root/programador com loja operacional na sessão deve usar essa loja em vendas/fiado.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';

void main() {
  group('LojaAtivaResolver.sessionStoreIfValid', () {
    const rootEmail = 'masterpalm26@gmail.com';
    const lojaNathy = 'nathy-pratas-e-folheados';
    const lojaRoot = 'masterpalm26';

    test('root com sessão Nathy retorna Nathy (não owner store)', () {
      final id = LojaAtivaResolver.sessionStoreIfValid(
        storeIdFromSessao: lojaNathy,
        storeIdFromConfig: lojaRoot,
        lastLojaIdFromConfig: lojaRoot,
        principalSessao: rootEmail,
        authEmail: rootEmail,
      );
      expect(id, lojaNathy);
    });

    test('usuário comum com store_id próprio na sessão', () {
      const email = 'natypolylopes1997@gmail.com';
      final id = LojaAtivaResolver.sessionStoreIfValid(
        storeIdFromSessao: lojaNathy,
        storeIdFromConfig: null,
        lastLojaIdFromConfig: null,
        principalSessao: email,
        authEmail: email,
      );
      expect(id, lojaNathy);
    });

    test('principal mismatch → null (não usar loja de outra conta)', () {
      final id = LojaAtivaResolver.sessionStoreIfValid(
        storeIdFromSessao: lojaNathy,
        storeIdFromConfig: lojaNathy,
        lastLojaIdFromConfig: lojaNathy,
        principalSessao: 'outro@gmail.com',
        authEmail: rootEmail,
      );
      expect(id, isNull);
    });

    test('sem loja na sessão → null (exige seleção antes de vender)', () {
      final id = LojaAtivaResolver.sessionStoreIfValid(
        storeIdFromSessao: '',
        storeIdFromConfig: '',
        lastLojaIdFromConfig: '',
        principalSessao: rootEmail,
        authEmail: rootEmail,
      );
      expect(id, isNull);
    });

    test('Hive box de contas a receber usa loja ativa da sessão', () {
      expect(
        HiveBoxNames.contasReceber(lojaNathy),
        'contas_receber_nathy-pratas-e-folheados',
      );
      expect(
        HiveBoxNames.contasReceber(lojaRoot),
        'contas_receber_masterpalm26',
      );
    });

    test('mensagem de erro sem loja ativa', () {
      expect(
        kErroSemLojaAtiva,
        contains('Selecione uma loja antes de vender'),
      );
    });
  });
}
