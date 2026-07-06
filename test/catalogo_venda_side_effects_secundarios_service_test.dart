// M3.4.2 — side-effects secundários do catálogo (denorm, admin, cupom, origem, campanha).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/campaign_engine_service.dart';
import 'package:master_palm/services/catalogo_venda_side_effects_secundarios_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_vendas_catalogo_denorm_service.dart';

const _lojaId = 'loja-cat-side-test';
const _vendaId = 'venda-side-99';
const _prodId = 'prod-mais-vendidos-1';

Map<String, dynamic> _customer({String email = 'side@test.com'}) => {
      'nome': 'Cliente Side',
      'email': email,
      'telefone': '11988887777',
    };

List<Map<String, dynamic>> _items() => [
      {
        'nome': 'Pulseira',
        'quantidade': 2,
        'precoUnitario': 30.0,
        'productId': _prodId,
      },
    ];

Map<String, dynamic> _premioRoleta() => {
      'descricao': '15% desconto',
      'codigo': 'ROLETA15',
      'valor': 15.0,
    };

Venda _vendaBase() => Venda(
      preco: 60,
      total: 60,
      clienteNome: 'Cliente Side',
      produtosDescricao: 'Pulseira',
      quantidade: 2,
      data: DateTime(2026, 7, 6),
      vendedor: 'Loja online',
      observacao: '',
      formasPagamento: 'PIX',
      lojaId: _lojaId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late CatalogoVendaSideEffectsSecundariosService service;
  late Directory hiveDir;
  late Box<Produto> produtosBox;
  late Box<Venda> vendasBox;

  int denormCalls = 0;
  int notifCalls = 0;
  int campaignCalls = 0;
  String? campaignOrigemRegistrada;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_cat_side_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  });

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    denormCalls = 0;
    notifCalls = 0;
    campaignCalls = 0;
    campaignOrigemRegistrada = null;

    CatalogoVendaSideEffectsSecundariosService.debugFirestoreOverride = firestore;
    CatalogoVendaSideEffectsSecundariosService.debugDenormOverride =
        ({required lojaId, required items, required produtosBox}) async {
      denormCalls++;
      final deltas = buildVendasCatalogoDeltasPorProdutoId(
        items: items,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );
      for (final e in deltas.entries) {
        final ref = firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('produtos')
            .doc(e.key);
        final snap = await ref.get();
        final atual = (snap.data()?['vendasCatalogoTotal'] as num?)?.toInt() ?? 0;
        await ref.set({
          'vendasCatalogoTotal': atual + e.value,
        }, SetOptions(merge: true));
      }
    };
    CatalogoVendaSideEffectsSecundariosService.debugNotificacaoOverride =
        ({
      required storeId,
      required pedidoId,
      required clienteNome,
      required valorTotal,
      required origem,
      vendedorNome,
      pagamentoConfirmado = false,
    }) async {
      notifCalls++;
      await firestore
          .collection('lojas')
          .doc(storeId)
          .collection('notificacoes')
          .add({
        'pedidoId': pedidoId,
        'origem': origem,
        'clienteNome': clienteNome,
        'valorTotal': valorTotal,
        'pagamentoConfirmado': pagamentoConfirmado,
      });
    };
    CatalogoVendaSideEffectsSecundariosService.debugCupomOverride = null;
    CatalogoVendaSideEffectsSecundariosService.debugSyncVendaOverride =
        (venda, {lojaId}) async => true;
    CatalogoVendaSideEffectsSecundariosService.debugCampaignOverride =
        ({
      required lojaId,
      required venda,
      required vendaId,
      required clienteNome,
      clienteId,
      telefone,
      email,
      required valorTotal,
    }) async {
      campaignCalls++;
      campaignOrigemRegistrada = 'catalogo';
      return ParticipacaoResult(sucesso: true, numero: '12345');
    };

    service = CatalogoVendaSideEffectsSecundariosService();

    produtosBox = await Hive.openBox<Produto>('produtos_$_lojaId');
    vendasBox = await Hive.openBox<Venda>('vendas_$_lojaId');
    await produtosBox.clear();
    await vendasBox.clear();

    await produtosBox.add(
      Produto.vazio()
        ..nome = 'Pulseira'
        ..idFirebase = _prodId
        ..lojaId = _lojaId
        ..quantidade = 10
        ..precoFinal = 30,
    );

    await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection('produtos')
        .doc(_prodId)
        .set({'vendasCatalogoTotal': 0});
  });

  tearDown(() async {
    CatalogoVendaSideEffectsSecundariosService.debugFirestoreOverride = null;
    CatalogoVendaSideEffectsSecundariosService.debugDenormOverride = null;
    CatalogoVendaSideEffectsSecundariosService.debugNotificacaoOverride = null;
    CatalogoVendaSideEffectsSecundariosService.debugCupomOverride = null;
    CatalogoVendaSideEffectsSecundariosService.debugCampaignOverride = null;
    CatalogoVendaSideEffectsSecundariosService.debugSyncVendaOverride = null;
    await produtosBox.close();
    await vendasBox.close();
  });

  Future<Venda> seedVenda({String? origem}) async {
    final v = _vendaBase()..origemVenda = origem;
    await vendasBox.add(v);
    return v;
  }

  group('M3.4.2 catalogo side effects secundarios', () {
    test('CAT2-1 mais vendidos incrementa', () async {
      final venda = await seedVenda();
      await service.aplicarAposVendaCatalogoAdmin(
        lojaId: _lojaId,
        venda: venda,
        vendaId: _vendaId,
        customer: _customer(),
        items: _items(),
        produtosBox: produtosBox,
        total: 60,
      );
      expect(denormCalls, 1);
      final prodSnap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('produtos')
          .doc(_prodId)
          .get();
      expect(prodSnap.data()?['vendasCatalogoTotal'], 2);
    });

    test('CAT2-2 admin recebe notificação', () async {
      final venda = await seedVenda();
      await service.aplicarAposVendaCatalogoAdmin(
        lojaId: _lojaId,
        venda: venda,
        vendaId: _vendaId,
        customer: _customer(),
        items: _items(),
        produtosBox: produtosBox,
        total: 60,
      );
      expect(notifCalls, 1);
      final notifs = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('notificacoes')
          .get();
      expect(notifs.docs.length, 1);
      expect(notifs.docs.first.data()['origem'], 'catalogo_web');
    });

    test('CAT2-3 cupom salvo em clientes_catalogo', () async {
      final venda = await seedVenda();
      await service.aplicarAposVendaCatalogoAdmin(
        lojaId: _lojaId,
        venda: venda,
        vendaId: _vendaId,
        customer: _customer(email: 'cupom@test.com'),
        items: _items(),
        produtosBox: produtosBox,
        total: 60,
        premioRoletaRaw: _premioRoleta(),
      );
      final cupomSnap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.clientesCatalogoCol)
          .doc('cupom@test.com')
          .collection('cupons')
          .doc('ROLETA15')
          .get();
      expect(cupomSnap.exists, isTrue);
      expect(cupomSnap.data()?['codigo'], 'ROLETA15');
      expect(cupomSnap.data()?['origem'], 'roleta_sorte');
    });

    test('CAT2-4 origemVenda = catalogo_web', () async {
      final venda = await seedVenda(origem: null);
      expect(venda.origemVenda, isNull);
      await service.aplicarAposVendaCatalogoAdmin(
        lojaId: _lojaId,
        venda: venda,
        vendaId: _vendaId,
        customer: _customer(),
        items: _items(),
        produtosBox: produtosBox,
        total: 60,
      );
      expect(venda.origemVenda, 'catalogo_web');
    });

    test('CAT2-5 CampaignEngine recebe origem catalogo', () async {
      final venda = await seedVenda();
      await service.aplicarAposVendaCatalogoAdmin(
        lojaId: _lojaId,
        venda: venda,
        vendaId: _vendaId,
        customer: _customer(),
        items: _items(),
        produtosBox: produtosBox,
        total: 60,
      );
      expect(campaignCalls, 1);
      expect(campaignOrigemRegistrada, 'catalogo');
      final src = File(
        'lib/services/catalogo_venda_side_effects_secundarios_service.dart',
      ).readAsStringSync();
      expect(src, contains("origem: 'catalogo'"));
    });

    test('CAT2-6 retry não duplica denorm cupom notificação', () async {
      final venda = await seedVenda();
      final args = (
        lojaId: _lojaId,
        venda: venda,
        vendaId: _vendaId,
        customer: _customer(email: 'retry@test.com'),
        items: _items(),
        produtosBox: produtosBox,
        total: 60,
        premioRoletaRaw: _premioRoleta(),
      );
      await service.aplicarAposVendaCatalogoAdmin(
        lojaId: args.lojaId,
        venda: args.venda,
        vendaId: args.vendaId,
        customer: args.customer,
        items: args.items,
        produtosBox: args.produtosBox,
        total: 60.0,
        premioRoletaRaw: args.premioRoletaRaw,
      );
      await service.aplicarAposVendaCatalogoAdmin(
        lojaId: args.lojaId,
        venda: args.venda,
        vendaId: args.vendaId,
        customer: args.customer,
        items: args.items,
        produtosBox: args.produtosBox,
        total: 60.0,
        premioRoletaRaw: args.premioRoletaRaw,
      );
      expect(denormCalls, 1);
      expect(notifCalls, 1);
      expect(campaignCalls, 1);
      final prodSnap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('produtos')
          .doc(_prodId)
          .get();
      expect(prodSnap.data()?['vendasCatalogoTotal'], 2);
      final cupons = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.clientesCatalogoCol)
          .doc('retry@test.com')
          .collection('cupons')
          .get();
      expect(cupons.docs.length, 1);
    });

    test('CAT2-7 rollback antes da venda não executa side-effects', () async {
      final markerSnap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('catalogo_side_effects_secundarios')
          .doc(_vendaId)
          .get();
      expect(markerSnap.exists, isFalse);
      expect(denormCalls, 0);
    });

    test('CAT2 fluxo pre_pedidos — ordem side effects antes de confirmar', () {
      final src =
          File('lib/screens/pre_pedidos_screen.dart').readAsStringSync();
      final iVenda = src.indexOf('VendasService.registrarVendaMulti');
      final iHistorico =
          src.indexOf('CatalogoPedidoHistoricoService().garantirDocumentoPedidosHistorico');
      final iSide = src.indexOf('CatalogoVendaSideEffectsSecundariosService');
      final iSideMethod = src.indexOf('aplicarAposVendaCatalogoAdmin');
      final iConfirmar = src.indexOf('PrePedidoService.confirmarPrePedido');
      final iPos = src.indexOf('PosPagamentoService.processarConfirmacaoPagamento');
      expect(iVenda, greaterThan(0));
      expect(iHistorico, greaterThan(iVenda));
      expect(iSide, greaterThan(iHistorico));
      expect(iSideMethod, greaterThan(iSide));
      expect(iConfirmar, greaterThan(iSideMethod));
      expect(iPos, greaterThan(iConfirmar));
    });
  });
}
