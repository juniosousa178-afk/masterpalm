// Edição de venda atômica (saleEdit) — cliente. Local/sintético; sem Firebase de produção.

import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/catalog_publish_service.dart';
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';
import 'package:master_palm/services/venda_edicao_estoque_diff.dart';
import 'package:master_palm/services/vendas_firestore_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mesmas chaves aceitas por `parseSaleEditPayload` (functions/src/stockCatalogSaleEdit.js).
const _serverSaleKeys = {
  'clienteNome', 'clienteId', 'produtosDescricao', 'quantidade', 'preco', 'total',
  'formasPagamento', 'frete', 'desconto', 'descontoValor', 'observacao',
  'pagamentoDinheiro', 'pagamentoPix', 'pagamentoCartao', 'taxas', 'custoProdutos',
  'tamanho', 'vendedor', 'vendedorUid', 'vendedorNome', 'vendedorEmail',
  'itens', 'origemCusto', 'itensComboSelecaoJson', 'saldoFiado',
  'quantidadeParcelasFiado', 'intervaloParcelasDias', 'dataVencimentoFiado', 'data',
};
const _serverLineKeys = {
  'produtoNome', 'quantidade', 'tamanho', 'cor', 'precoUnitario', 'precoTotal',
  'productId', 'variacaoExtraResumo', 'extraValor', 'custoUnitario', 'origemCustoItem',
};

FirebaseFunctionsException _fx(String code, String message, [Map<String, dynamic>? details]) =>
    FirebaseFunctionsException(code: code, message: message, details: details);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('saleEditLinesHash — paridade com o servidor', () {
    test('vetores do servidor (V1, V2)', () {
      final v1 = [
        VendaItem(produtoNome: 'Anel', quantidade: 1, precoUnitario: 0, tamanho: '20', cor: 'Rubelita', productId: 'anel'),
        VendaItem(produtoNome: 'Letra', quantidade: 2, precoUnitario: 0, tamanho: '', cor: 'Gold', extraValor: 'J', productId: 'letra'),
        VendaItem(produtoNome: 'Sem ID  Antigo', quantidade: 1, precoUnitario: 0, tamanho: '', cor: ''),
        VendaItem(produtoNome: 'Lilás', quantidade: 3, precoUnitario: 0, tamanho: 'P', cor: 'LILÁS', productId: 'brinco-ç'),
      ];
      expect(VendaEdicaoEstoqueDiff.saleEditLinesHash(v1),
          'a6f28cf0fe70d104f1264fc12d4b90caa3cf410cbdfcb871c1f99328f8ed986a');
      expect(VendaEdicaoEstoqueDiff.saleEditLinesHash(const []),
          '4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945');
    });

    test('independe da ordem, agrega linhas iguais e ignora preço/nome com productId', () {
      VendaItem it(String pid, int q, {String nome = 'X', double preco = 1, String cor = ''}) =>
          VendaItem(produtoNome: nome, quantidade: q, precoUnitario: preco, cor: cor, productId: pid);
      final a = [it('a', 1), it('b', 2, cor: 'Azul')];
      final b = [it('b', 1, cor: ' azul '), it('a', 1, nome: 'Outro', preco: 99), it('b', 1, cor: 'AZUL')];
      expect(VendaEdicaoEstoqueDiff.saleEditLinesHash(a), VendaEdicaoEstoqueDiff.saleEditLinesHash(b));
      expect(VendaEdicaoEstoqueDiff.saleEditLinesHash([it('a', 2)]),
          isNot(VendaEdicaoEstoqueDiff.saleEditLinesHash([it('a', 1)])));
    });

    test('operationId determinístico por sessão + conteúdo', () {
      String id(String intent, Map<String, dynamic> p) => VendaEdicaoEstoqueDiff.buildSaleEditOperationId(
            lojaId: 'l', saleId: 's', editIntentId: intent, originalLinesHash: 'h', salePayload: p);
      expect(id('i1', {'a': 1}), id('i1', {'a': 1}));
      expect(id('i1', {'a': 1}), isNot(id('i2', {'a': 1})));
      expect(id('i1', {'a': 1}), isNot(id('i1', {'a': 2})));
      expect(RegExp(r'^saleedit_[0-9a-f]{64}$').hasMatch(id('i1', {})), isTrue);
    });
  });

  group('saleEditSalePayload', () {
    Venda venda({double total = 100, double pix = 100, String formas = 'Pagamento Pix: R\$ 100,00'}) => Venda(
          clienteNome: 'Cliente',
          produtosDescricao: 'desc',
          quantidade: 1,
          preco: total,
          total: total,
          formasPagamento: formas,
          data: DateTime.utc(2026, 9, 20, 12),
          vendedor: 'App',
          observacao: '',
          pagamentoPix: pix,
          itens: [VendaItem(produtoNome: 'P', quantidade: 1, precoUnitario: total, productId: 'p')],
        );

    test('só envia campos permitidos pelo servidor; data em ISO UTC', () {
      final p = VendasFirestoreService.saleEditSalePayload(venda());
      expect(_serverSaleKeys.containsAll(p.keys), isTrue, reason: '${p.keys}');
      for (final line in p['itens'] as List) {
        expect(_serverLineKeys.containsAll((line as Map).keys), isTrue);
      }
      expect(p['data'], '2026-09-20T12:00:00.000Z');
      expect(p.containsKey('saldoFiado'), isFalse);
      for (final k in ['id', 'createdAt', 'stockOperationId', 'lojaId', 'statusVenda']) {
        expect(p.containsKey(k), isFalse, reason: k);
      }
    });

    test('fiado aberto envia saldo e vencimento ISO', () {
      final p = VendasFirestoreService.saleEditSalePayload(
        venda(pix: 40, formas: 'Pagamento Pix: R\$ 40,00\nFiado - R\$ 60,00. Vencimento: 20/10/2026'),
      );
      expect(p['saldoFiado'], closeTo(60, 0.001));
      expect(p['dataVencimentoFiado'], isA<String>());
      expect(DateTime.tryParse(p['dataVencimentoFiado'] as String), isNotNull);
    });
  });

  group('mapeamento de erros por código estruturado', () {
    const atualizados = 'Os dados de estoque deste produto foram atualizados';

    test('failed-precondition genérico não vira "dados atualizados"', () {
      for (final msg in [
        'Stock protocol unavailable or migration incomplete',
        'Product unavailable',
        'Variation not found',
        'Sale lines conflict',
      ]) {
        final e = _fx('failed-precondition', msg);
        expect(formatDartErrorForUser(e), isNot(contains(atualizados)), reason: msg);
        expect(formatSalvarVendaErrorForUser(e), isNot(contains(atualizados)), reason: msg);
      }
    });

    test('STOCK_CHANGED continua "dados atualizados"', () {
      final e = _fx('failed-precondition', 'Stock revision conflict', {'code': 'STOCK_CHANGED'});
      expect(formatSalvarVendaErrorForUser(e), contains(atualizados));
      expect(formatDartErrorForUser(_fx('aborted', 'Stock revision conflict')), contains(atualizados));
    });

    test('cada código tem mensagem própria', () {
      final casos = <String, (Map<String, dynamic>, String)>{
        'legacy': ({'code': 'LEGACY_PROTOCOL_BLOCKED', 'reason': 'KIND_restock'}, 'Atualize o aplicativo'),
        'insuf': ({'code': 'INSUFFICIENT_STOCK'}, 'Estoque insuficiente'),
        'grade': ({'code': 'GRADE_SELECTION_REQUIRED'}, 'tamanho/cor'),
        'conflict': ({'code': 'SALE_EDIT_CONFLICT', 'reason': 'ORIGINAL_LINES_CHANGED'}, 'outro aparelho'),
        'payload': ({'code': 'OPERATION_PAYLOAD_CONFLICT'}, 'outros dados'),
        'pid': ({'code': 'INVALID_SALE_EDIT', 'reason': 'LINE_PRODUCT_ID_REQUIRED'}, 'não está vinculado'),
        'combo': ({'code': 'INVALID_SALE_EDIT', 'reason': 'COMBO_EDIT_NOT_SUPPORTED'}, 'combo'),
        'big': ({'code': 'INVALID_SALE_EDIT', 'reason': 'SALE_EDIT_TOO_LARGE'}, '25 produtos'),
      };
      casos.forEach((nome, c) {
        final e = _fx('failed-precondition', 'x', c.$1);
        expect(formatSalvarVendaErrorForUser(e), contains(c.$2), reason: nome);
        expect(formatSalvarVendaErrorForUser(e), isNot(contains(atualizados)), reason: nome);
      });
    });
  });

  group('linhasRemotasAutoritativasDivergem (proteção do syncVenda)', () {
    Venda local(int q) => Venda(
          clienteNome: 'C', produtosDescricao: '', quantidade: 1, preco: 0, total: 0,
          formasPagamento: '', data: DateTime(2026), vendedor: 'App', observacao: '',
          itens: [VendaItem(produtoNome: 'A', quantidade: q, precoUnitario: 1, productId: 'a')],
        );
    Map<String, dynamic> remoto(int q, {int? rev}) => {
          'itens': [VendasFirestoreService.itemParaFirestore(
              VendaItem(produtoNome: 'A', quantidade: q, precoUnitario: 1, productId: 'a'))],
          if (rev != null) 'saleEditRevision': rev,
        };

    test('só protege documentos editados pelo servidor com linhas diferentes', () {
      expect(VendasFirestoreService.linhasRemotasAutoritativasDivergem(remote: remoto(2, rev: 1), local: local(1), lojaId: 'l'), isTrue);
      expect(VendasFirestoreService.linhasRemotasAutoritativasDivergem(remote: remoto(1, rev: 1), local: local(1), lojaId: 'l'), isFalse);
      expect(VendasFirestoreService.linhasRemotasAutoritativasDivergem(remote: remoto(2), local: local(1), lojaId: 'l'), isFalse);
    });
  });

  group('editarVendaMulti via saleEdit', () {
    const lojaId = 'loja-sale-edit-atomic';
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;
    late List<Map<String, dynamic>> chamadas;
    late Object? Function(Map<String, dynamic> payload) respostaServidor;
    late Map<String, dynamic>? remoto;
    late int syncBaseChamadas;
    late bool syncBaseOk;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_sale_edit_atomic_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
      if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
      if (!Hive.isAdapterRegistered(29)) Hive.registerAdapter(ContaReceberAdapter());
    });

    tearDownAll(() async {
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    Map<String, dynamic> produtoServidor(String id, int qtd) => {
          'productId': id, 'nome': id.toUpperCase(), 'slug': id, 'quantidade': qtd,
          'variacoes': <String, dynamic>{}, 'estoquePorCor': <String, dynamic>{},
          'estoquePorTamanho': <String, dynamic>{}, 'stockRevision': 7, 'stockOperationId': 'op',
        };

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      LojaAtivaResolver.debugResolveOverride = ({String origem = 'app'}) async => lojaId;
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;
      ContaReceberFirestoreService.debugFirestoreOverride = firestore;
      CatalogoSyncService.debugFirestoreOverride = firestore;
      CatalogPublishService.debugFirestoreOverride = firestore;
      VendasService.debugEditarVendaSyncClienteOverride = (_, {required lojaId}) async {};
      VendasService.debugEditarVendaSyncVendaOverride = (_, {required lojaId}) async => true;

      chamadas = [];
      respostaServidor = (p) => {
            'alreadyApplied': false,
            'operationId': p['operationId'],
            'products': [produtoServidor('a', 3)],
            'saleId': 'sale-1',
            'saleEditRevision': 1,
            'saleCommitted': true,
            'stockChanged': true,
          };
      StockCatalogBackendService.debugTransport = (name, data) async {
        chamadas.add({'name': name, ...data});
        final r = respostaServidor(data);
        if (r is Exception) throw r;
        return Map<String, dynamic>.from(r as Map);
      };
      syncBaseChamadas = 0;
      syncBaseOk = true;
      VendasService.debugSyncVendaBaseEdicao = (venda, loja) async {
        syncBaseChamadas++;
        if (syncBaseOk) venda.idFirebase ??= 'sale-1';
        return syncBaseOk;
      };
      VendasService.debugLerVendaRemotaEdicao = (_, __) async => remoto;

      final stamp = DateTime.now().microsecondsSinceEpoch;
      produtosBox = await Hive.openBox<Produto>('prod_sea_$stamp');
      clientesBox = await Hive.openBox<Cliente>('cli_sea_$stamp');
      vendasBox = await Hive.openBox<Venda>('vendas_sea_$stamp');
      for (final (id, q) in [('a', 4), ('b', 4)]) {
        await firestore.collection('lojas').doc(lojaId).collection('estoque_produtos').doc(id).set({
          'nome': id.toUpperCase(), 'quantidade': q, 'stockKind': 'simple', 'stockRevision': 1,
          'stockOperationId': 'seed',
        });
        await produtosBox.add(Produto.vazio()
          ..nome = id.toUpperCase()
          ..idFirebase = id
          ..lojaId = lojaId
          ..quantidade = q
          ..precoFinal = 10
          ..stockRevision = 1);
      }
      await clientesBox.add(Cliente(
          nome: 'Cliente SEA', telefone: '', instagram: '', cep: '', cidade: '', lojaId: lojaId));
    });

    tearDown(() async {
      StockCatalogBackendService.debugTransport = null;
      VendasService.debugSyncVendaBaseEdicao = null;
      VendasService.debugLerVendaRemotaEdicao = null;
      VendasService.debugEditarVendaSyncClienteOverride = null;
      VendasService.debugEditarVendaSyncVendaOverride = null;
      LojaAtivaResolver.debugResolveOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
      ContaReceberFirestoreService.debugFirestoreOverride = null;
      CatalogoSyncService.debugFirestoreOverride = null;
      CatalogPublishService.debugFirestoreOverride = null;
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
      try {
        await Hive.deleteBoxFromDisk(HiveBoxNames.contasReceber(lojaId));
      } catch (_) {}
    });

    VendaItem linha(String pid, int q) =>
        VendaItem(produtoNome: pid.toUpperCase(), quantidade: q, precoUnitario: 10, productId: pid);

    Future<Venda> vendaSalva(List<VendaItem> itens, {String? id = 'sale-1'}) async {
      final total = itens.fold<double>(0, (a, i) => a + i.precoUnitario * i.quantidade);
      final v = Venda(
        clienteNome: 'Cliente SEA', produtosDescricao: 'orig', quantidade: itens.length,
        preco: total, total: total, formasPagamento: 'Pagamento Pix: R\$ $total',
        data: DateTime(2026, 9, 20), vendedor: 'App', observacao: 'orig', itens: itens,
        pagamentoPix: total, lojaId: lojaId, idFirebase: id,
      );
      await vendasBox.add(v);
      remoto = id == null
          ? null
          : {'itens': itens.map(VendasFirestoreService.itemParaFirestore).toList(), 'lojaId': lojaId};
      return v;
    }

    Future<Venda> editar(Venda v, List<VendaItem> itens, {String intent = 'intent-1', String obs = 'editada'}) {
      final total = itens.fold<double>(0, (a, i) => a + i.precoUnitario * i.quantidade);
      return VendasService.editarVendaMulti(
        vendaOriginal: v, produtosBox: produtosBox, clientesBox: clientesBox, vendasBox: vendasBox,
        clienteNome: 'Cliente SEA', clienteExistente: clientesBox.values.first,
        itens: itens, pix: total, lojaId: lojaId, observacao: obs, saleEditIntentId: intent,
      );
    }

    List<Map<String, dynamic>> comandosEstoque() =>
        chamadas.where((c) => c['name'] == 'stockCatalogCommand').toList();

    test('mista A 1→2, B 1→0: um único comando saleEdit, sem sale/restock', () async {
      final v = await vendaSalva([linha('a', 1), linha('b', 1)]);
      final hashOriginal = VendaEdicaoEstoqueDiff.saleEditLinesHash(v.itensOuVazio);
      await editar(v, [linha('a', 2)]);

      final cmds = comandosEstoque();
      expect(cmds, hasLength(1));
      expect(cmds.single['kind'], 'saleEdit');
      expect(cmds.single.containsKey('items'), isFalse);
      expect(RegExp(r'^saleedit_[0-9a-f]{64}$').hasMatch(cmds.single['operationId'] as String), isTrue);
      final se = cmds.single['saleEdit'] as Map;
      expect(se['saleId'], 'sale-1');
      expect(se['expectedOriginalLinesHash'], hashOriginal);
      expect((se['sale'] as Map)['itens'], hasLength(1));

      final salva = vendasBox.values.single;
      expect(salva.itensOuVazio.single.quantidade, 2);
      expect(salva.observacao, 'editada');
      final a = produtosBox.values.firstWhere((p) => p.idFirebase == 'a');
      expect(a.quantidade, 3, reason: 'Hive projeta o valor autoritativo do servidor');
    });

    test('rejeição do servidor: venda local e estoque local intactos', () async {
      for (final details in [
        {'code': 'INSUFFICIENT_STOCK'},
        {'code': 'LEGACY_PROTOCOL_BLOCKED'},
        {'code': 'SALE_EDIT_CONFLICT', 'reason': 'ORIGINAL_LINES_CHANGED'},
      ]) {
        chamadas.clear();
        await vendasBox.clear();
        final v = await vendaSalva([linha('a', 1), linha('b', 1)]);
        respostaServidor = (_) => _fx('failed-precondition', 'x', details);
        Object? erro;
        try {
          await editar(v, [linha('a', 2)]);
        } catch (e) {
          erro = e;
        }
        expect(erro, isNotNull, reason: '$details');
        final salva = vendasBox.values.single;
        expect(salva.itensOuVazio.map((i) => '${i.productId}:${i.quantidade}').toList(), ['a:1', 'b:1']);
        expect(salva.observacao, 'orig');
        expect(salva.total, 20);
        expect(produtosBox.values.firstWhere((p) => p.idFirebase == 'a').quantidade, 4);
        expect(formatSalvarVendaErrorForUser(erro!), isNot(contains('foram atualizados')));
      }
    });

    test('retentativa na mesma sessão reutiliza o operationId; outra sessão gera outro', () async {
      final v = await vendaSalva([linha('a', 1)]);
      respostaServidor = (_) => _fx('unavailable', 'offline');
      await expectLater(editar(v, [linha('a', 2)]), throwsA(anything));
      final primeiro = comandosEstoque().first['operationId'];
      expect(comandosEstoque().map((c) => c['operationId']).toSet(), {primeiro});
      chamadas.clear();
      await expectLater(editar(v, [linha('a', 2)]), throwsA(anything));
      expect(comandosEstoque().first['operationId'], primeiro);
      chamadas.clear();
      await expectLater(editar(v, [linha('a', 2)], intent: 'intent-2'), throwsA(anything));
      expect(comandosEstoque().first['operationId'], isNot(primeiro));
    });

    test('nuvem com edição autoritativa mais nova: hidrata local e não envia comando', () async {
      final v = await vendaSalva([linha('a', 1)]);
      remoto = {
        'itens': [VendasFirestoreService.itemParaFirestore(linha('a', 3))],
        'saleEditRevision': 2,
        'total': 30.0,
        'clienteNome': 'Cliente SEA',
      };
      await expectLater(editar(v, [linha('a', 2)]), throwsA(isA<VendaEdicaoConflitoException>()));
      expect(comandosEstoque(), isEmpty);
      expect(vendasBox.values.single.itensOuVazio.single.quantidade, 3);
      expect(vendasBox.values.single.total, 30.0);
    });

    test('venda ainda não sincronizada: sincroniza a base antes; falha → nada enviado', () async {
      final v = await vendaSalva([linha('a', 1)], id: null);
      syncBaseOk = false;
      await expectLater(editar(v, [linha('a', 2)]), throwsA(isA<Exception>()));
      expect(syncBaseChamadas, 1);
      expect(comandosEstoque(), isEmpty);
      expect(vendasBox.values.single.itensOuVazio.single.quantidade, 1);

      syncBaseOk = true;
      await editar(v, [linha('a', 2)]);
      expect(syncBaseChamadas, 2);
      expect(comandosEstoque(), hasLength(1));
    });

    test('edição sem mudança de linhas não chama o servidor de estoque', () async {
      final v = await vendaSalva([linha('a', 1)]);
      await editar(v, [linha('a', 1)], obs: 'só observação');
      expect(comandosEstoque(), isEmpty);
      expect(vendasBox.values.single.observacao, 'só observação');
    });
  });
}
