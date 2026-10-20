import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/catalog/catalog_initial_web_route.dart';
import 'package:master_palm/catalog/checkout_single_flight.dart';
import 'package:master_palm/catalog/public_order_link.dart';
import 'package:master_palm/config/app_urls.dart';
import 'package:master_palm/repositories/pedido_status_publico_repository.dart';
import 'package:master_palm/screens/pedido_publico_screen.dart';
import 'package:master_palm/services/pre_pedido_service.dart';

const _lojaA = 'loja-a';
const _lojaB = 'loja-b';
const _pedidoA = 'PedidoAaaaaaaaaaaaaa';
const _pedidoB = 'PedidoBbbbbbbbbbbbbb';
const _pedidoC = 'PedidoCcccccccccccccc';

CatalogRouteDecision _decide(String url) => CatalogRouteDecision.fromUri(
      Uri.parse(url),
      isDefaultAppOrCatalogHostingHost: AppUrls.isDefaultMasterPalmCatalogHost,
      isPublicMarketingHost: AppUrls.isPublicMarketingHost,
    );

Map<String, dynamic> _mirror(String lojaId, String pedidoId, String item,
        {double total = 10}) =>
    {
      'pedidoId': pedidoId,
      'lojaId': lojaId,
      'status': 'pendente',
      'total': total,
      'itensResumo': [
        {'nome': item, 'quantidade': 2},
      ],
    };

Future<FakeFirebaseFirestore> _fixture() async {
  final db = FakeFirebaseFirestore();
  Future<void> put(String loja, String pedido, Map<String, dynamic> data) =>
      db.doc('lojas/$loja/pedido_status_publico/$pedido').set(data);
  await put(_lojaA, _pedidoA, {
    ..._mirror(_lojaA, _pedidoA, 'Anel Pedido A', total: 59.9),
    'custo': 12.34,
    'margem': 0.8,
    'cliente': {'nome': 'NAO_EXIBIR'},
  });
  await put(_lojaA, _pedidoB, _mirror(_lojaA, _pedidoB, 'Colar Pedido B'));
  await put(_lojaB, _pedidoC, _mirror(_lojaB, _pedidoC, 'Brinco Pedido C'));
  return db;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  FakeFirebaseFirestore db, {
  required String lojaId,
  required String pedidoId,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: PedidoPublicoScreen(
      lojaId: lojaId,
      prePedidoId: pedidoId,
      repository: PedidoStatusPublicoRepository(db: db),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('link gerado para o WhatsApp', () {
    test('A. formato canônico: app, /pedido/{id}, ?loja={lojaId}', () {
      final url = PrePedidoService.gerarUrlPedido(
        prePedidoId: _pedidoA,
        lojaId: 'nathy-pratas-e-folheados',
      );
      expect(url,
          'https://app.mastepalm.com.br/pedido/$_pedidoA?loja=nathy-pratas-e-folheados');
      expect(url, isNot(contains('/c/')));
      expect(url, isNot(startsWith('https://mastepalm.com.br')));
      expect(PublicOrderLink.parse(Uri.parse(url)),
          const PublicOrderRef(lojaId: 'nathy-pratas-e-folheados', pedidoId: _pedidoA));
    });

    test('F. encoding: IDs com maiúsculas, hífen e underscore fazem round-trip exato', () {
      for (final (loja, pedido) in [
        ('LojaABC_1', 'abcDEF0123456789wxyz'),
        ('ericabrisasr-1', 'm3XSKVykTUEgeOmwVvVd'),
        ('masterpalm_gmail_com', '0Lg9UdsMyGdR7yPDfVhC'),
      ]) {
        final uri = PublicOrderLink.build(lojaId: loja, pedidoId: pedido);
        expect(PublicOrderLink.parse(Uri.parse(uri.toString())),
            PublicOrderRef(lojaId: loja, pedidoId: pedido));
      }
    });

    test('F. encoding: caracteres que quebram URL são rejeitados, nunca concatenados', () {
      for (final bad in [
        'loja a',
        'loja&x=1',
        'a/b',
        'a?b',
        'a#b',
        'ação',
        '',
        '../x',
        'x' * 129,
      ]) {
        expect(() => PublicOrderLink.build(lojaId: bad, pedidoId: _pedidoA),
            throwsArgumentError, reason: bad);
        expect(() => PublicOrderLink.build(lojaId: _lojaA, pedidoId: bad),
            throwsArgumentError, reason: bad);
      }
    });

    test('G. mensagem do WhatsApp mantém o conteúdo e troca só o link', () {
      final msg = PrePedidoService.formatarParaWhatsApp(
        prePedido: {
          'id': _pedidoA,
          'itens': [
            {'nome': 'Anel & Cia / "Prata"', 'quantidade': 2, 'precoUnitario': 10.0},
          ],
          'subtotal': 20.0,
          'frete': {'nome': 'Retirada', 'valor': 0.0},
          'total': 20.0,
          'pagamento': 'pix',
          'observacao': 'Entregar à tarde? #urgente',
        },
        lojaId: 'nathy-pratas-e-folheados',
      );
      expect(msg, startsWith('🛍️ Novo pedido'));
      expect(msg, contains('2x Anel & Cia / "Prata"'));
      expect(msg, contains('Total: R\$ 20,00'));
      expect(msg, contains('📝 Observações: Entregar à tarde? #urgente'));
      expect(
          msg,
          contains(
              '🔗 Ver pedido: https://app.mastepalm.com.br/pedido/$_pedidoA?loja=nathy-pratas-e-folheados'));
      expect(msg, isNot(contains('/c/')));
    });

    test('15. texto do wa.me é codificado uma vez; o link volta intacto ao decodificar', () {
      final msg = PrePedidoService.formatarParaWhatsApp(
        prePedido: {
          'id': _pedidoA,
          'itens': const [],
          'total': 1.0,
          'pagamento': 'pix',
          'observacao': 'linha 1\nlinha 2 & ? # /',
        },
        lojaId: 'LojaABC_1',
      );
      final waUrl =
          Uri.parse('https://wa.me/5511999999999?text=${Uri.encodeComponent(msg.trim())}');
      final text = waUrl.queryParameters['text']!;
      expect(text, msg.trim());
      expect(text, contains('\nlinha 2 & ? # /'));
      final link = RegExp(r'https://\S+').firstMatch(text)!.group(0)!;
      expect(link, 'https://app.mastepalm.com.br/pedido/$_pedidoA?loja=LojaABC_1');
      expect(link, isNot(contains('%25')));
      expect(PublicOrderLink.parse(Uri.parse(link)),
          const PublicOrderRef(lojaId: 'LojaABC_1', pedidoId: _pedidoA));
    });

    test('H. sem ID definitivo do pedido a mensagem não leva link', () {
      for (final id in [null, '', 'id inválido']) {
        final msg = PrePedidoService.formatarParaWhatsApp(
          prePedido: {'id': id, 'itens': const [], 'total': 1.0, 'pagamento': 'pix'},
          lojaId: _lojaA,
        );
        expect(msg, isNot(contains('Ver pedido')), reason: '$id');
        expect(msg, isNot(contains('http')), reason: '$id');
      }
    });
  });

  group('E. rota web direta / refresh', () {
    test('/pedido/{id}?loja= abre o pedido, não o catálogo legado', () {
      for (final host in [
        'https://app.mastepalm.com.br',
        'https://app.masterpalm.com.br',
        'https://masterpalm-58c46.web.app',
      ]) {
        final d = _decide('$host/pedido/$_pedidoA?loja=nathy-pratas-e-folheados');
        expect(d.kind, CatalogInitialRouteKind.publicOrder, reason: host);
      }
    });

    test('referência inválida em /pedido/ continua na página do pedido (erro amigável)', () {
      expect(_decide('https://app.mastepalm.com.br/pedido/x').kind,
          CatalogInitialRouteKind.publicOrder);
      expect(PublicOrderLink.parse(Uri.parse('https://app.mastepalm.com.br/pedido/x')),
          isNull);
      expect(
          PublicOrderLink.parse(
              Uri.parse('https://app.mastepalm.com.br/pedido/a%2Fb?loja=loja-a')),
          isNull);
    });

    test('catálogo e admin não mudam de rota', () {
      expect(_decide('https://app.mastepalm.com.br/loja/nathy').kind,
          CatalogInitialRouteKind.publicCatalogByLojaPath);
      expect(_decide('https://app.mastepalm.com.br/?loja=nathy').kind,
          CatalogInitialRouteKind.publicCatalogByLegacyQuery);
      expect(_decide('https://app.mastepalm.com.br/pedidos').kind,
          CatalogInitialRouteKind.appRoot);
      expect(_decide('https://app.mastepalm.com.br/').kind,
          CatalogInitialRouteKind.appRoot);
      expect(_decide('https://app.mastepalm.com.br/pagamento/sucesso?loja=x').kind,
          CatalogInitialRouteKind.appRoot);
    });

    test('index.html não trata /pedido/{id}?loja= como primeira pintura de catálogo', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html, contains("if (isPublicOrderPath(path)) return false;"));
      final fnStart = html.indexOf('function isPublicCatalogUrl()');
      final guard = html.indexOf('isPublicOrderPath(path)) return false', fnStart);
      final lojaCheck = html.indexOf('hasLojaPath(path)) return true', fnStart);
      expect(guard, greaterThan(fnStart));
      expect(guard, lessThan(lojaCheck));
    });

    test('main.dart despacha /pedido/ antes de qualquer detecção de catálogo', () {
      final src = File('lib/main.dart').readAsStringSync();
      final orderFastPath = src.indexOf('runApp(PublicOrderWebApp(');
      final catalogFastPath = src.indexOf('FAST PATH CIRÚRGICO');
      expect(orderFastPath, greaterThan(0));
      expect(orderFastPath, lessThan(catalogFastPath));
    });
  });

  group('página pública do pedido', () {
    testWidgets('A/13. abre exatamente o pedido A da loja A', (tester) async {
      final db = await _fixture();
      await _pumpScreen(tester, db, lojaId: _lojaA, pedidoId: _pedidoA);
      expect(find.text('Anel Pedido A'), findsOneWidget);
      expect(find.text(_pedidoA), findsOneWidget);
      expect(find.text('R\$ 59,90'), findsOneWidget);
      expect(find.text('Colar Pedido B'), findsNothing);
      expect(find.text('Brinco Pedido C'), findsNothing);
    });

    testWidgets('14. não exibe custo, margem nem dados de cliente do documento',
        (tester) async {
      final db = await _fixture();
      await _pumpScreen(tester, db, lojaId: _lojaA, pedidoId: _pedidoA);
      expect(find.textContaining('NAO_EXIBIR'), findsNothing);
      expect(find.textContaining('12,34'), findsNothing);
      expect(find.textContaining('12.34'), findsNothing);
      expect(find.textContaining('margem', findRichText: true), findsNothing);
    });

    testWidgets('B. pedido de outra loja: trocar a loja na URL não revela o pedido',
        (tester) async {
      final db = await _fixture();
      await _pumpScreen(tester, db, lojaId: _lojaA, pedidoId: _pedidoC);
      expect(find.text(PedidoPublicoScreen.mensagemNaoEncontrado), findsOneWidget);
      expect(find.text('Brinco Pedido C'), findsNothing);

      await _pumpScreen(tester, db, lojaId: _lojaB, pedidoId: _pedidoA);
      expect(find.text(PedidoPublicoScreen.mensagemNaoEncontrado), findsOneWidget);
      expect(find.text('Anel Pedido A'), findsNothing);
    });

    testWidgets('B. espelho com lojaId divergente do path é recusado', (tester) async {
      final db = FakeFirebaseFirestore();
      await db
          .doc('lojas/$_lojaA/pedido_status_publico/$_pedidoA')
          .set(_mirror(_lojaB, _pedidoA, 'Item de outra loja'));
      await _pumpScreen(tester, db, lojaId: _lojaA, pedidoId: _pedidoA);
      expect(find.text('Item de outra loja'), findsNothing);
      expect(find.text(PedidoPublicoScreen.mensagemNaoEncontrado), findsOneWidget);
    });

    testWidgets('C. pedido inexistente mostra mensagem amigável', (tester) async {
      final db = await _fixture();
      await _pumpScreen(tester, db, lojaId: _lojaA, pedidoId: 'NaoExiste0000000000x');
      expect(find.text(PedidoPublicoScreen.mensagemNaoEncontrado), findsOneWidget);
    });

    testWidgets('D. referência inválida não consulta o Firestore', (tester) async {
      final db = await _fixture();
      await _pumpScreen(tester, db, lojaId: 'loja a', pedidoId: _pedidoA);
      expect(find.text(PedidoPublicoScreen.mensagemLinkInvalido), findsOneWidget);
      expect(find.text('Anel Pedido A'), findsNothing);
    });
  });

  group('checkout WhatsApp', () {
    test('G/H/10/11. pedido é persistido antes do link; falha encerra sem abrir WhatsApp', () {
      final src = File('lib/screens/public_catalog_screen.dart').readAsStringSync();
      final start = src.indexOf('onCheckoutWhatsapp: ({');
      final end = src.indexOf('onCheckoutMercadoPago: ({', start);
      final body = src.substring(start, end);
      final criar = body.indexOf('PrePedidoService.criarPrePedido(');
      final nullGuard = body.indexOf("if (prePedido == null) {");
      final formatar = body.indexOf('PrePedidoService.formatarParaWhatsApp(');
      final abrir = body.indexOf('_openWhatsappSimple(');
      expect(criar, greaterThan(0));
      expect(criar, lessThan(nullGuard));
      expect(nullGuard, lessThan(formatar));
      expect(formatar, lessThan(abrir));
      final guardBlock = body.substring(nullGuard, body.indexOf('}', nullGuard));
      expect(guardBlock, contains('showErr('));
      expect(guardBlock, contains('return;'));
      final catchBlock = body.substring(
          body.indexOf("'❌ Erro ao criar pré-pedido"), formatar);
      expect(catchBlock, contains('return;'));
    });

    test('I. clique duplo: só uma execução em voo', () async {
      final flight = CheckoutSingleFlight();
      final gate = Completer<void>();
      var execucoes = 0;
      final primeira = flight.run(() async {
        execucoes++;
        await gate.future;
      });
      final segunda = flight.run(() async => execucoes++);
      expect(await segunda, isFalse);
      expect(flight.busy, isTrue);
      gate.complete();
      expect(await primeira, isTrue);
      expect(execucoes, 1);
      expect(flight.busy, isFalse);
    });

    test('J. retry após conclusão ou erro é permitido', () async {
      final flight = CheckoutSingleFlight();
      await expectLater(
          flight.run(() async => throw StateError('falha')), throwsStateError);
      expect(flight.busy, isFalse);
      var execucoes = 0;
      expect(await flight.run(() async => execucoes++), isTrue);
      expect(await flight.run(() async => execucoes++), isTrue);
      expect(execucoes, 2);
    });

    test('I. botão do WhatsApp usa a guarda síncrona', () {
      final src = File('lib/screens/public_catalog/widgets/carrinho_sheet_web.dart')
          .readAsStringSync();
      expect(src, contains('_whatsappCheckoutFlight.run(() async {'));
    });
  });
}
