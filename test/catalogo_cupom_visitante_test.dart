// M3.7-HOMOLOG-FINAL — H13 cupom público vs pessoal (CUPOMVIS)

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/catalogo_cupom_visitante_policy.dart';
import 'package:master_palm/models/cupom.dart';

Cupom _cupomPublico() => Cupom(
      id: 'c1',
      codigo: 'PROMO10',
      nome: 'Promo',
      valor: 10,
      tipo: 'percentual',
      ativo: true,
      criadoEm: DateTime(2026),
    );

Cupom _cupomPessoal() => Cupom(
      id: 'c2',
      codigo: 'VIP10',
      nome: 'VIP',
      valor: 10,
      tipo: 'percentual',
      clienteId: 'cliente-1',
      ativo: true,
      criadoEm: DateTime(2026),
    );

void main() {
  group('CUPOMVIS — política visitante', () {
    test('CUPOMVIS-1 público sem login', () {
      final r = resolverCupomPublicoFirestore(
        cupom: _cupomPublico(),
        clienteLogado: false,
      );
      expect(r.status, CatalogoCupomResolverStatus.encontradoPublico);
      expect(r.cupomMap?['codigo'], 'PROMO10');
      expect(r.cupomMap?['origem'], 'cupom_publico_loja');
    });

    test('CUPOMVIS-2 público logado', () {
      final r = resolverCupomPublicoFirestore(
        cupom: _cupomPublico(),
        clienteLogado: true,
      );
      expect(r.status, CatalogoCupomResolverStatus.encontradoPublico);
    });

    test('CUPOMVIS-3 pessoal sem login bloqueado', () {
      final r = resolverCupomPublicoFirestore(
        cupom: _cupomPessoal(),
        clienteLogado: false,
      );
      expect(r.status, CatalogoCupomResolverStatus.bloqueadoPessoalSemLogin);
      expect(r.mensagem, catalogoCupomPessoalExigeLoginMsg);
    });

    test('CUPOMVIS-4 pessoal logado permitido na resolução pública', () {
      final r = resolverCupomPublicoFirestore(
        cupom: _cupomPessoal(),
        clienteLogado: true,
      );
      expect(r.status, CatalogoCupomResolverStatus.encontradoPublico);
    });

    test('CUPOMVIS-5 config pública vs pessoal', () {
      expect(
        catalogoCupomConfigEhPublico({'codigo': 'A', 'ativo': true}),
        isTrue,
      );
      expect(
        catalogoCupomConfigEhPublico({
          'codigo': 'B',
          'ativo': true,
          'clienteId': 'x',
        }),
        isFalse,
      );
    });

    test('CUPOMVIS-6 visitante sem login — mensagem pessoal', () {
      expect(
        mensagemCupomNaoEncontradoVisitante(clienteLogado: false),
        catalogoCupomPessoalExigeLoginMsg,
      );
    });

    test('CUPOMVIS-7 código roleta parece pessoal', () {
      expect(catalogoCupomCodigoParecePessoal('PREMIO-ABC'), isTrue);
      expect(catalogoCupomCodigoParecePessoal('PROMO10'), isFalse);
    });

    test('CUPOMVIS-8 cupom inexistente', () {
      final r = resolverCupomPublicoFirestore(
        cupom: null,
        clienteLogado: false,
      );
      expect(r.status, CatalogoCupomResolverStatus.naoEncontrado);
    });
  });
}
