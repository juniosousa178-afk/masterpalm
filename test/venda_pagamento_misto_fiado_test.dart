// Venda com pagamento misto (parte agora + saldo fiado).

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/screens/nova_venda/finalizar_confirmacao_dialog.dart';
import 'package:master_palm/widgets/moeda_text_field.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/safe_cast.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-misto-fiado-20260602';

  group('calcularSaldoFiado / validarParametrosVendaFiada', () {
    test('saldo fiado = total - pago agora', () {
      expect(
        VendasService.calcularSaldoFiado(total: 300, totalPagoAgora: 120),
        closeTo(180, 0.01),
      );
    });

    test('fiado sem cliente bloqueia', () {
      expect(
        () => VendasService.validarParametrosVendaFiada(
          isFiado: true,
          dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
          clienteNome: '',
          total: 300,
          totalPagoAgora: 120,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fiado com saldo e sem vencimento bloqueia', () {
      expect(
        () => VendasService.validarParametrosVendaFiada(
          isFiado: true,
          dataVencimentoFiado: null,
          clienteNome: 'Ana',
          total: 300,
          totalPagoAgora: 120,
        ),
        throwsA(
          predicate<ArgumentError>(
            (e) => e.message.toString().contains('vencimento'),
          ),
        ),
      );
    });

    test('pagamento maior que total bloqueia', () {
      expect(
        () => VendasService.validarParametrosVendaFiada(
          isFiado: true,
          dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
          clienteNome: 'Ana',
          total: 300,
          totalPagoAgora: 350,
        ),
        throwsA(
          predicate<ArgumentError>(
            (e) => e.message.toString().contains('maior que o total'),
          ),
        ),
      );
    });

    test('fiado integral pago não exige vencimento', () {
      expect(
        () => VendasService.validarParametrosVendaFiada(
          isFiado: true,
          dataVencimentoFiado: null,
          clienteNome: 'Ana',
          total: 300,
          totalPagoAgora: 300,
        ),
        returnsNormally,
      );
    });
  });

  group('FinalizarVendaConfirmacaoDialog — pagamento adiantado fiado', () {
    Future<void> abrirDialog(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await FinalizarVendaConfirmacaoDialog.show(
                      ctx,
                      total: 300,
                      resumoProdutos: const [
                        {'produto': 'Produto', 'quantidade': 1, 'preco': 300.0},
                      ],
                      initialPagamentos: const [
                        {'forma': 'Pix', 'valor': 0.0},
                      ],
                    );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('marca fiado zera pagamento adiantado', (tester) async {
      await abrirDialog(tester);

      final campo = tester.widget<MoedaTextField>(find.byType(MoedaTextField).first);
      expect(campo.controller.text, '300,00');

      await tester.tap(find.text('Venda fiada (conta a receber)'));
      await tester.pumpAndSettle();

      final campoZerado =
          tester.widget<MoedaTextField>(find.byType(MoedaTextField).first);
      expect(campoZerado.controller.text, isEmpty);
      expect(find.text('Saldo fiado: R\$ 300,00'), findsOneWidget);
    });

    testWidgets('confirmar fiado sem alterar pagamento retorna lista vazia',
        (tester) async {
      FinalizarVendaResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await FinalizarVendaConfirmacaoDialog.show(
                      ctx,
                      total: 300,
                      resumoProdutos: const [
                        {'produto': 'Produto', 'quantidade': 1, 'preco': 300.0},
                      ],
                      initialPagamentos: const [
                        {'forma': 'Pix', 'valor': 0.0},
                      ],
                    );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Venda fiada (conta a receber)'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirmar venda').last,
      );
      await tester.pumpAndSettle();

      final r = result;
      expect(r, isNotNull);
      expect(r!.isFiado, isTrue);
      expect(r.pagamentos, isEmpty);
      expect(r.trocoTotal, 0);
    });

    testWidgets('venda normal mantém sugestão do total no pagamento',
        (tester) async {
      await abrirDialog(tester);
      final campo = tester.widget<MoedaTextField>(find.byType(MoedaTextField).first);
      expect(campo.controller.text, '300,00');
      expect(find.text('Preencher total'), findsOneWidget);
    });

    testWidgets('pagamento maior que total bloqueia confirmar em fiado',
        (tester) async {
      await abrirDialog(tester);
      await tester.tap(find.text('Venda fiada (conta a receber)'));
      await tester.pumpAndSettle();

      final campo = find.byType(MoedaTextField).first;
      await tester.enterText(campo, '35000');
      await tester.pumpAndSettle();

      final botao = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirmar venda'),
      );
      expect(botao.onPressed, isNull);
    });
  });

  group('registrarVendaMulti pagamento misto', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_misto_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
      if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
      if (!Hive.isAdapterRegistered(29)) {
        Hive.registerAdapter(ContaReceberAdapter());
      }
    });

    tearDownAll(() async {
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;

      produtosBox = await Hive.openBox<Produto>(
        'prod_misto_${DateTime.now().microsecondsSinceEpoch}',
      );
      clientesBox = await Hive.openBox<Cliente>(
        'cli_misto_${DateTime.now().microsecondsSinceEpoch}',
      );
      vendasBox = await Hive.openBox<Venda>(
        'vendas_misto_${DateTime.now().microsecondsSinceEpoch}',
      );

      const productId = 'prod-misto-1';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({'nome': 'Produto Misto', 'quantidade': 10});

      final p = Produto.vazio()
        ..nome = 'Produto Misto'
        ..idFirebase = productId
        ..lojaId = lojaId
        ..quantidade = 10
        ..precoFinal = 100;
      await produtosBox.add(p);

      await clientesBox.add(
        Cliente(
          nome: 'Cliente Misto',
          telefone: '11988887777',
          instagram: '',
          cep: '',
          cidade: '',
          lojaId: lojaId,
        ),
      );
    });

    tearDown(() async {
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
      try {
        await Hive.deleteBoxFromDisk(HiveBoxNames.contasReceber(lojaId));
      } catch (_) {}
    });

    Future<Venda> vender({
      required Cliente cliente,
      required int qtd,
      double pix = 0,
      double dinheiro = 0,
      double cartao = 0,
      bool isFiado = false,
      DateTime? venc,
    }) {
      return VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Produto Misto',
            quantidade: qtd,
            precoUnitario: 100,
            productId: 'prod-misto-1',
          ),
        ],
        pix: pix,
        dinheiro: dinheiro,
        cartao: cartao,
        lojaId: lojaId,
        isFiado: isFiado,
        dataVencimentoFiado: venc,
      );
    }

    test('Pix R\$ 120 + fiado → venda R\$ 300, estoque -3, CR R\$ 180', () async {
      final cliente = clientesBox.values.first;
      final venc = DateTime.now().add(const Duration(days: 30));

      final venda = await vender(
        cliente: cliente,
        qtd: 3,
        pix: 120,
        isFiado: true,
        venc: venc,
      );

      expect(venda.total, closeTo(300, 0.01));
      expect(venda.pagamentoPix, closeTo(120, 0.01));
      expect(venda.formasPagamento, contains('Pix'));
      expect(venda.formasPagamento.toLowerCase(), contains('fiado'));

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 1);
      final cr = crBox.values.first;
      expect(cr.valor, closeTo(180, 0.01));
      expect(cr.valorOriginal, closeTo(180, 0.01));
      expect(cr.vendaKey, hiveKeyOrNull(venda.key));
      await crBox.close();

      expect(produtosBox.values.first.quantidade, 7);
    });

    test('pagamento integral com fiado marcado não cria conta', () async {
      final cliente = clientesBox.values.first;

      await vender(
        cliente: cliente,
        qtd: 2,
        pix: 200,
        isFiado: true,
        venc: DateTime.now().add(const Duration(days: 30)),
      );

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 0);
      await crBox.close();
    });

    test('fiado R\$ 300 sem pagamento agora cria CR R\$ 300', () async {
      final cliente = clientesBox.values.first;
      final venc = DateTime.now().add(const Duration(days: 30));

      final venda = await vender(
        cliente: cliente,
        qtd: 3,
        isFiado: true,
        venc: venc,
      );

      expect(venda.total, closeTo(300, 0.01));
      expect(venda.pagamentoPix, 0);
      expect(venda.pagamentoDinheiro, 0);
      expect(venda.pagamentoCartao, 0);

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 1);
      expect(crBox.values.first.valor, closeTo(300, 0.01));
      await crBox.close();
    });

    test('fiado R\$ 300 com R\$ 120 agora cria CR R\$ 180', () async {
      final cliente = clientesBox.values.first;
      await vender(
        cliente: cliente,
        qtd: 3,
        pix: 120,
        isFiado: true,
        venc: DateTime.now().add(const Duration(days: 30)),
      );

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 1);
      expect(crBox.values.first.valor, closeTo(180, 0.01));
      await crBox.close();
    });

    test('fiado R\$ 300 com R\$ 300 pago manualmente não cria CR', () async {
      final cliente = clientesBox.values.first;
      await vender(
        cliente: cliente,
        qtd: 3,
        pix: 300,
        isFiado: true,
        venc: DateTime.now().add(const Duration(days: 30)),
      );

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 0);
      await crBox.close();
    });

    test('venda fiada integral continua criando CR pelo total', () async {
      final cliente = clientesBox.values.first;
      final venc = DateTime.now().add(const Duration(days: 20));

      await vender(
        cliente: cliente,
        qtd: 1,
        isFiado: true,
        venc: venc,
      );

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 1);
      expect(crBox.values.first.valor, closeTo(100, 0.01));
      await crBox.close();
    });

    test('excluir venda mista remove contas vinculadas', () async {
      final cliente = clientesBox.values.first;
      final venda = await vender(
        cliente: cliente,
        qtd: 2,
        pix: 50,
        isFiado: true,
        venc: DateTime.now().add(const Duration(days: 15)),
      );
      final vk = hiveKeyOrNull(venda.key);
      expect(vk, isNotNull);

      await VendasService.removerContasReceberVinculadasAVenda(
        lojaId: lojaId,
        vendaKey: vk!,
      );

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 0);
      await crBox.close();
    });
  });
}
