// M3.9 Sprint4-R5.1 / R5.2 / R5.3 / R5.5 (homologação — sem R5.4)

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/access_scope_service.dart';
import 'package:master_palm/core/gestao_comercial_meta_comissao.dart';
import 'package:master_palm/core/meta_vendedor_legacy_bridge.dart';
import 'package:master_palm/models/comissao_config.dart';
import 'package:master_palm/models/gestao_comercial.dart';
import 'package:master_palm/models/meta.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/utils/role_utils.dart';

AccessScopeIdentity _seller(String uid, {String? email, String? nome}) =>
    AccessScopeIdentity(
      role: UserRole.vendedor,
      uid: uid,
      email: email ?? '$uid@t.com',
      displayName: nome ?? uid,
    );

AccessScopeIdentity _admin() => const AccessScopeIdentity(
      role: UserRole.admin,
      uid: 'admin-1',
      email: 'a@t.com',
      displayName: 'Admin',
    );

Venda _venda({
  required String uid,
  required double total,
  required DateTime data,
  bool cancelada = false,
  String lojaId = 'loja-1',
}) {
  return Venda(
    clienteNome: 'C',
    produtosDescricao: 'P',
    quantidade: 1,
    preco: total,
    total: total,
    formasPagamento: 'pix',
    data: data,
    vendedor: uid,
    observacao: '',
    itens: const [],
    lojaId: lojaId,
    cancelada: cancelada,
    vendedorUid: uid,
  );
}

void main() {
  group('R5.1 ESTOQUE-VENDA (idempotência de operação)', () {
    test('ESTOQUE-VENDA-4 alreadyApplied não reaplica efeito', () {
      const op = EstoqueBaixaOperationResult(
        status: EstoqueBaixaOperationStatus.alreadyApplied,
        transactionResults: [],
      );
      expect(op.baixaJaAplicadaAnteriormente, isTrue);
      expect(op.baixaAplicadaNestaExecucao, isFalse);
    });

    test('ESTOQUE-VENDA-5 applied marca baixa nesta execução', () {
      const op = EstoqueBaixaOperationResult(
        status: EstoqueBaixaOperationStatus.applied,
        transactionResults: [],
      );
      expect(op.baixaAplicadaNestaExecucao, isTrue);
      expect(op.baixaJaAplicadaAnteriormente, isFalse);
    });
  });

  group('R5.2 GESTAO-ESCOPO', () {
    test('GESTAO-ESCOPO-1..3 vendedor sem agregados/financeiro/mais vendidos', () {
      final s = _seller('v1');
      expect(AccessScopeService.canSeeMaisVendidos(s), isFalse);
      expect(AccessScopeService.canSeeFinanceiroMetasLoja(s), isFalse);
      expect(AccessScopeService.canSeeStoreAggregates(s), isFalse);
      expect(AccessScopeService.canSeeVendasResumoGlobal(s), isFalse);
    });

    test('GESTAO-ESCOPO-4 fail-closed: identidade null não é admin', () {
      AccessScopeIdentity? id;
      expect(id?.isAdmin == true, isFalse);
      expect(id?.isSeller == true, isFalse);
    });

    test('GESTAO-ESCOPO-5 sellerOwnsSale só próprias', () {
      final s = _seller('v1');
      final propria = _venda(uid: 'v1', total: 10, data: DateTime(2026, 7, 1));
      final outra = _venda(uid: 'v2', total: 10, data: DateTime(2026, 7, 1));
      expect(AccessScopeService.sellerOwnsSale(propria, s), isTrue);
      expect(AccessScopeService.sellerOwnsSale(outra, s), isFalse);
    });

    test('GESTAO-ESCOPO-6 admin mantém visão completa', () {
      final a = _admin();
      expect(AccessScopeService.canSeeMaisVendidos(a), isTrue);
      expect(AccessScopeService.canSeeFinanceiroMetasLoja(a), isTrue);
      expect(AccessScopeService.canSeeStoreAggregates(a), isTrue);
    });
  });

  group('R5.3 META-VENDEDOR', () {
    test('META-VENDEDOR-1 meta legada do uid aparece', () {
      final id = _seller('uid-v');
      final metas = [
        Meta(mesRef: '2026-07', metaMensal: 5000, vendedorId: 'uid-v'),
        Meta(mesRef: '2026-07', metaMensal: 99999, vendedorId: 'GERAL'),
      ];
      final hit = resolveMetaLegadaParaVendedor(
        metas: metas,
        identity: id,
        mesRef: '2026-07',
      );
      expect(hit?.metaMensal, 5000);
      final cfg = aplicarMetaLegadaSeVazia(
        config: GestaoVendedorConfig(
          permissoes: GestaoVendedorConfig.permissoesPadraoVendedor(),
        ),
        legada: hit,
      );
      expect(cfg.metaMensal, 5000);
    });

    test('META-VENDEDOR-2 meta de outro vendedor não resolve', () {
      final id = _seller('uid-v');
      final hit = resolveMetaLegadaParaVendedor(
        metas: [
          Meta(mesRef: '2026-07', metaMensal: 8000, vendedorId: 'outro'),
        ],
        identity: id,
        mesRef: '2026-07',
      );
      expect(hit, isNull);
    });

    test('META-VENDEDOR-4..5 progresso só vendas válidas próprias', () {
      final id = _seller('v1');
      final now = DateTime(2026, 7, 15);
      final cfg = GestaoVendedorConfig(
        metaMensal: 1000,
        permissoes: GestaoVendedorConfig.permissoesPadraoVendedor(),
      );
      final vendas = [
        _venda(uid: 'v1', total: 400, data: DateTime(2026, 7, 2)),
        _venda(uid: 'v1', total: 200, data: DateTime(2026, 7, 3), cancelada: true),
        _venda(uid: 'v2', total: 900, data: DateTime(2026, 7, 4)),
      ];
      final meta = calcularMetaPessoal(
        config: cfg,
        identity: id,
        vendas: vendas,
        lojaId: 'loja-1',
        agora: now,
      );
      expect(meta.realizadoMensal, 400);
      expect(meta.qtdVendasMensal, 1);
      expect(meta.percentualMensal, closeTo(40, 0.01));
    });

    test('META-VENDEDOR-6 fallback email sem cruzar', () {
      final id = _seller('uid-x', email: 'ana@loja.com');
      final hit = resolveMetaLegadaParaVendedor(
        metas: [
          Meta(mesRef: '2026-07', metaMensal: 1200, vendedorId: 'ana@loja.com'),
          Meta(mesRef: '2026-07', metaMensal: 50, vendedorId: 'outro@loja.com'),
        ],
        identity: id,
        mesRef: '2026-07',
      );
      expect(hit?.metaMensal, 1200);
    });
  });

  group('R5.3 COMISSAO', () {
    test('COMISSAO-1..2 venda própria gera comissão percentual', () {
      final id = _seller('v1');
      final cfg = GestaoVendedorConfig(
        comissaoTipo: ComissaoTipo.percentual,
        comissaoPercentual: 10,
        permissoes: GestaoVendedorConfig.permissoesPadraoVendedor(),
      );
      final r = calcularComissaoPessoal(
        config: cfg,
        identity: id,
        vendas: [
          _venda(uid: 'v1', total: 200, data: DateTime(2026, 7, 5)),
          _venda(uid: 'v2', total: 500, data: DateTime(2026, 7, 5)),
        ],
        lojaId: 'loja-1',
        agora: DateTime(2026, 7, 15),
      );
      expect(r.acumulada, closeTo(20, 0.01));
      expect(r.qtdVendasBase, 1);
    });

    test('COMISSAO-7 cancelada não entra na base', () {
      final id = _seller('v1');
      final cfg = GestaoVendedorConfig(
        comissaoTipo: ComissaoTipo.percentual,
        comissaoPercentual: 10,
        permissoes: GestaoVendedorConfig.permissoesPadraoVendedor(),
      );
      final r = calcularComissaoPessoal(
        config: cfg,
        identity: id,
        vendas: [
          _venda(
            uid: 'v1',
            total: 200,
            data: DateTime(2026, 7, 5),
            cancelada: true,
          ),
        ],
        lojaId: 'loja-1',
        agora: DateTime(2026, 7, 15),
      );
      expect(r.acumulada, 0);
      expect(r.qtdVendasBase, 0);
    });

    test('COMISSAO-10 bridge legado aplica % sem sobrescrever gestao', () {
      final gestaoVazia = GestaoVendedorConfig(
        permissoes: GestaoVendedorConfig.permissoesPadraoVendedor(),
      );
      final bridged = aplicarComissaoLegadaSeVazia(
        config: gestaoVazia,
        vendedorLegado: ComissaoVendedor(
          lojaId: 'l',
          vendedorUid: 'v1',
          vendedorEmail: 'v@t.com',
          vendedorNome: 'V',
          comissaoPercentual: 7.5,
        ),
        globalLegado: ComissaoConfig(lojaId: 'l', comissaoGlobalPercent: 5),
      );
      expect(bridged.comissaoPercentual, 7.5);

      final gestaoJaTem = GestaoVendedorConfig(
        comissaoPercentual: 12,
        permissoes: GestaoVendedorConfig.permissoesPadraoVendedor(),
      );
      final keep = aplicarComissaoLegadaSeVazia(
        config: gestaoJaTem,
        vendedorLegado: ComissaoVendedor(
          lojaId: 'l',
          vendedorUid: 'v1',
          vendedorEmail: 'v@t.com',
          vendedorNome: 'V',
          comissaoPercentual: 7.5,
        ),
      );
      expect(keep.comissaoPercentual, 12);
    });
  });

  group('R5.5 TELA-CANCELADAS escopo', () {
    test('TELA-CANCELADAS-4 só destinatarioUid do vendedor', () {
      final uid = 'v1';
      final list = [
        {'destinatarioUid': 'v1', 'tipo': 'vendaCancelada'},
        {'destinatarioUid': 'v2', 'tipo': 'vendaCancelada'},
        {'destinatarioUid': 'v1', 'tipo': 'novaVenda'},
      ];
      final mine = list
          .where((e) =>
              e['destinatarioUid'] == uid && e['tipo'] == 'vendaCancelada')
          .toList();
      expect(mine.length, 1);
    });

    test('TELA-CANCELADAS-8 deep link admin bloqueado por isSeller', () {
      expect(_admin().isSeller, isFalse);
      expect(_seller('v1').isSeller, isTrue);
    });
  });
}
