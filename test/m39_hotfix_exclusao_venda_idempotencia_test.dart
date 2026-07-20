// M3.9 HOTFIX — exclusão de venda idempotente (estoque / meta / notificação)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/access_scope_service.dart';
import 'package:master_palm/core/gestao_comercial_meta_comissao.dart';
import 'package:master_palm/core/venda_exclusao_tombstone.dart';
import 'package:master_palm/core/venda_metrics_filter.dart';
import 'package:master_palm/models/gestao_comercial.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/notificacao_vendas_service.dart';
import 'package:master_palm/utils/role_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

Venda _v({
  required String uid,
  required double total,
  required DateTime data,
  String? idFirebase,
  bool cancelada = false,
  String lojaId = 'loja-x',
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
    idFirebase: idFirebase,
  );
}

AccessScopeIdentity _seller(String uid) => AccessScopeIdentity(
      role: UserRole.vendedor,
      uid: uid,
      email: '$uid@t.com',
      displayName: uid,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    VendaExclusaoTombstone.resetForTests();
  });

  group('EXCLUSAO estoque idempotência multi-id', () {
    test('EXCLUSAO-1/5 qualquer id candidato bloqueia 2º estorno', () async {
      SharedPreferences.setMockInitialValues({
        'estoque_devolvido_v1_loja-x_op-aaa': true,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('estoque_devolvido_v1_loja-x_op-aaa'), isTrue);

      final ja = await EstoqueTransactionService.devolucaoVendaJaAplicadaEmQualquerId(
        'loja-x',
        ['hive_9', 'op-aaa', 'hive_99'],
      );
      expect(ja, isTrue);

      final nao = await EstoqueTransactionService.devolucaoVendaJaAplicadaEmQualquerId(
        'loja-x',
        ['hive_1', 'outro'],
      );
      expect(nao, isFalse);
    });

    test('EXCLUSAO-6 marcarDevolucaoLocalEmTodosIds cobre hive+firebase', () async {
      await EstoqueTransactionService.marcarDevolucaoLocalEmTodosIds(
        'loja-x',
        ['hive_3', '58562f8a-6f55-4ab5-8b95-b9020a393fea'],
      );
      expect(
        await EstoqueTransactionService.devolucaoVendaJaAplicada(
          'loja-x',
          'hive_3',
        ),
        isTrue,
      );
      expect(
        await EstoqueTransactionService.devolucaoVendaJaAplicada(
          'loja-x',
          '58562f8a-6f55-4ab5-8b95-b9020a393fea',
        ),
        isTrue,
      );
    });
  });

  group('EXCLUSAO meta/comissão', () {
    test('EXCLUSAO-3 tombstone remove venda da meta', () async {
      await VendaExclusaoTombstone.registrar(
        lojaId: 'loja-x',
        idFirebase: '58562f8a-6f55-4ab5-8b95-b9020a393fea',
        hiveKey: 7,
      );
      final tombs = await VendaExclusaoTombstone.idsParaLoja('loja-x');
      final id = _seller('v1');
      final cfg = GestaoVendedorConfig(
        metaMensal: 1000,
        permissoes: GestaoVendedorConfig.permissoesPadraoVendedor(),
      );
      final vendas = [
        _v(
          uid: 'v1',
          total: 400,
          data: DateTime(2026, 7, 2),
          idFirebase: '58562f8a-6f55-4ab5-8b95-b9020a393fea',
        ),
        _v(uid: 'v1', total: 100, data: DateTime(2026, 7, 3)),
      ];
      expect(
        incluirVendaEmMetricas(vendas[0], tombstonesExclusao: tombs),
        isFalse,
      );
      final meta = calcularMetaPessoal(
        config: cfg,
        identity: id,
        vendas: vendas,
        lojaId: 'loja-x',
        agora: DateTime(2026, 7, 15),
        tombstonesExclusao: tombs,
      );
      expect(meta.realizadoMensal, 100);
      expect(meta.qtdVendasMensal, 1);
    });

    test('EXCLUSAO-4 tombstone remove da comissão', () async {
      await VendaExclusaoTombstone.registrar(
        lojaId: 'loja-x',
        idFirebase: 'venda-c1',
      );
      final tombs = await VendaExclusaoTombstone.idsParaLoja('loja-x');
      final r = calcularComissaoPessoal(
        config: GestaoVendedorConfig(
          comissaoTipo: ComissaoTipo.percentual,
          comissaoPercentual: 10,
          permissoes: GestaoVendedorConfig.permissoesPadraoVendedor(),
        ),
        identity: _seller('v1'),
        vendas: [
          _v(
            uid: 'v1',
            total: 200,
            data: DateTime(2026, 7, 5),
            idFirebase: 'venda-c1',
          ),
        ],
        lojaId: 'loja-x',
        agora: DateTime(2026, 7, 15),
        tombstonesExclusao: tombs,
      );
      expect(r.acumulada, 0);
      expect(r.qtdVendasBase, 0);
    });
  });

  group('EXCLUSAO notificação', () {
    test('EXCLUSAO-2/7 doc idempotente: 2ª chamada não cria outro doc', () async {
      final db = FakeFirebaseFirestore();
      // Exercita a chave estável sem Firebase real no service (unit da regra).
      final docId1 = NotificacaoVendasService.docIdExclusaoIdempotenteForTest(
        storeId: 'loja-x',
        vendedorUid: 'v1',
        pedidoId: '58562f8a-6f55-4ab5-8b95-b9020a393fea',
        tipoAcao: 'excluida',
      );
      final docId2 = NotificacaoVendasService.docIdExclusaoIdempotenteForTest(
        storeId: 'loja-x',
        vendedorUid: 'v1',
        pedidoId: '58562f8a-6f55-4ab5-8b95-b9020a393fea',
        tipoAcao: 'excluida',
      );
      expect(docId1, docId2);
      expect(docId1.startsWith('vx_'), isTrue);

      final ref = db
          .collection('lojas')
          .doc('loja-x')
          .collection('notificacoes')
          .doc(docId1);
      await ref.set({'pedidoId': '58562f8a-6f55-4ab5-8b95-b9020a393fea'});
      final snap = await ref.get();
      expect(snap.exists, isTrue);
      // Segunda "gravação" com mesmo id sobrescreve 1 doc — nunca 4 docs.
      await ref.set({'pedidoId': '58562f8a-6f55-4ab5-8b95-b9020a393fea', 'n': 2});
      final all = await db
          .collection('lojas')
          .doc('loja-x')
          .collection('notificacoes')
          .get();
      expect(all.docs.length, 1);
    });
  });
}
