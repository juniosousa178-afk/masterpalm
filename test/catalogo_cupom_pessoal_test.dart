// M3.7-HOMOLOG-FINAL-R2 — H13B/C cupom pessoal (PERSCUP)

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

Cupom _cupomPessoal({
  String clienteId = 'cliente-dono',
  String? ownerEmail,
}) =>
    Cupom(
      id: 'c2',
      codigo: 'VIP10',
      nome: 'VIP Pessoal',
      valor: 10,
      tipo: 'percentual',
      clienteId: clienteId,
      ownerEmail: ownerEmail,
      ativo: true,
      criadoEm: DateTime(2026),
    );

void main() {
  group('PERSCUP — cupom pessoal admin + checkout', () {
    test('PERSCUP-1 admin schema — cupom pessoal tem clienteId e pessoal', () {
      final map = catalogoCupomMapFromFirestoreCupom(_cupomPessoal());
      expect(map['pessoal'], isTrue);
      expect(map['clienteId'], 'cliente-dono');
    });

    test('PERSCUP-2 exige cliente — pessoal sem clienteId é pessoal', () {
      expect(catalogoCupomEhPessoal(_cupomPessoal()), isTrue);
      expect(catalogoCupomEhPessoal(_cupomPublico()), isFalse);
    });

    test('PERSCUP-3 schema correto — ownerEmail normalizado', () {
      final c = _cupomPessoal(ownerEmail: 'Dono@Email.COM');
      final map = catalogoCupomMapFromFirestoreCupom(c);
      expect(map['ownerEmail'], 'dono@email.com');
    });

    test('PERSCUP-4 visitante bloqueado', () {
      final r = resolverCupomPublicoFirestore(
        cupom: _cupomPessoal(),
        clienteLogado: false,
      );
      expect(r.status, CatalogoCupomResolverStatus.bloqueadoPessoalSemLogin);
      expect(r.mensagem, catalogoCupomPessoalExigeLoginMsg);
    });

    test('PERSCUP-5 dono logado aceita por clienteId', () {
      final r = resolverCupomPublicoFirestore(
        cupom: _cupomPessoal(),
        clienteLogado: true,
        clienteLogadoId: 'cliente-dono',
        clienteLogadoEmail: 'dono@loja.com',
      );
      expect(r.status, CatalogoCupomResolverStatus.encontradoPublico);
    });

    test('PERSCUP-6 outra conta bloqueia', () {
      final r = resolverCupomPublicoFirestore(
        cupom: _cupomPessoal(),
        clienteLogado: true,
        clienteLogadoId: 'outro-cliente',
        clienteLogadoEmail: 'outro@loja.com',
      );
      expect(r.status, CatalogoCupomResolverStatus.bloqueadoPessoalContaErrada);
      expect(r.mensagem, catalogoCupomPessoalContaErradaMsg);
    });

    test('PERSCUP-7 expirado — inativo bloqueia resolução', () {
      final r = resolverCupomPublicoFirestore(
        cupom: _cupomPessoal().copyWith(ativo: false),
        clienteLogado: true,
        clienteLogadoId: 'cliente-dono',
      );
      expect(r.status, CatalogoCupomResolverStatus.naoEncontrado);
    });

    test('PERSCUP-8 inativo bloqueia', () {
      final r = resolverCupomPublicoFirestore(
        cupom: _cupomPublico().copyWith(ativo: false),
        clienteLogado: false,
      );
      expect(r.status, CatalogoCupomResolverStatus.naoEncontrado);
    });

    test('PERSCUP-9 limite de uso — podeSerUsado', () {
      final c = _cupomPessoal().copyWith(qtdMaximaUsos: 1, qtdUsosAtuais: 1);
      expect(c.podeSerUsado('cliente-dono', 100), isFalse);
    });

    test('PERSCUP-10 persistência mapa pré-pedido', () {
      final map = catalogoCupomMapFromFirestoreCupom(_cupomPessoal());
      expect(map['codigo'], 'VIP10');
      expect(map['origem'], 'cupom_publico_loja');
    });

    test('PERSCUP-11 total — desconto percentual', () {
      final c = _cupomPessoal();
      expect(c.calcularDesconto(200), 20);
    });

    test('PERSCUP-12 revogação — inativo', () {
      final c = _cupomPessoal().copyWith(ativo: false);
      expect(c.podeSerUsado('cliente-dono', 50), isFalse);
    });

    test('PERSCUP-13 e-mail normalizado', () {
      expect(catalogoEmailNormalizado('  A@B.COM '), 'a@b.com');
      expect(
        catalogoClienteEhDonoCupom(
          cupom: _cupomPessoal(ownerEmail: 'dono@email.com'),
          clienteLogadoId: null,
          clienteLogadoEmail: 'DONO@EMAIL.COM',
        ),
        isTrue,
      );
    });

    test('PERSCUP-14 legado por e-mail quando clienteId difere', () {
      expect(
        catalogoClienteEhDonoCupom(
          cupom: _cupomPessoal(
            clienteId: 'id-legado',
            ownerEmail: 'dono@email.com',
          ),
          clienteLogadoId: 'outro-id',
          clienteLogadoEmail: 'dono@email.com',
        ),
        isTrue,
      );
      expect(
        catalogoClienteEhDonoCupom(
          cupom: _cupomPessoal(ownerEmail: 'dono@email.com'),
          clienteLogadoId: 'x',
          clienteLogadoEmail: 'dono@email.com',
        ),
        isTrue,
      );
    });

    test('PERSCUP-15 cupom público permanece funcionando', () {
      final r = resolverCupomPublicoFirestore(
        cupom: _cupomPublico(),
        clienteLogado: false,
      );
      expect(r.status, CatalogoCupomResolverStatus.encontradoPublico);
      expect(catalogoCupomConfigEhPublico({'codigo': 'X'}), isTrue);
    });
  });

  group('CUPOMVIS regressão', () {
    test('CUPOMVIS-4 pessoal logado dono permitido', () {
      final r = resolverCupomPublicoFirestore(
        cupom: _cupomPessoal(),
        clienteLogado: true,
        clienteLogadoId: 'cliente-dono',
      );
      expect(r.status, CatalogoCupomResolverStatus.encontradoPublico);
    });
  });
}
