import 'dart:io';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/catalog/public_order_item_image.dart';
import 'package:master_palm/models/pedido_status_publico.dart';
import 'package:master_palm/repositories/pedido_status_publico_repository.dart';
import 'package:master_palm/screens/pedido_publico_screen.dart';
import 'package:master_palm/services/pre_pedido_service.dart';
import 'package:master_palm/widgets/public_order_item_thumbnail.dart';

const _lojaA = 'loja-a';
const _lojaB = 'loja-b';
const _pedido = 'PedidoAaaaaaaaaaaaaa';
const _nomeEstojo = 'Estojo Veludo Rosa Anel/brinco/pingente/berloque';
const _nomeAnel = 'Anel Pedra Lux';
const _imgEstojo =
    'https://firebasestorage.googleapis.com/v0/b/masterpalm-58c46.appspot.com/o/lojas%2Floja-a%2Fprodutos%2Festojo%2F00.jpg?alt=media&token=t1';
const _imgAnel =
    'https://firebasestorage.googleapis.com/v0/b/masterpalm-58c46.appspot.com/o/lojas%2Floja-a%2Fprodutos%2Fanel%2F00.jpg?alt=media&token=t2';

final _png1x1 = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
final _invalidBytes = Uint8List.fromList(const [1, 2, 3, 4]);

final _placeholder = find.byKey(const ValueKey('public-order-item-placeholder'));

Map<String, dynamic> _mirror(
  String lojaId,
  List<Map<String, dynamic>> itens, {
  double total = 74.5,
  String status = 'pendente',
}) =>
    {
      'pedidoId': _pedido,
      'lojaId': lojaId,
      'status': status,
      'total': total,
      'itensResumo': itens,
    };

const _doisProdutos = [
  {'nome': _nomeEstojo, 'quantidade': 1, 'imagem': _imgEstojo},
  {'nome': _nomeAnel, 'quantidade': 1, 'imagem': _imgAnel},
];

Future<FakeFirebaseFirestore> _db(String lojaId, Map<String, dynamic> mirror) async {
  final db = FakeFirebaseFirestore();
  await db.doc('lojas/$lojaId/pedido_status_publico/$_pedido').set(mirror);
  return db;
}

Future<List<String>> _pump(
  WidgetTester tester,
  FakeFirebaseFirestore db, {
  String lojaId = _lojaA,
  Uint8List? bytes,
}) async {
  final pedidas = <String>[];
  await tester.pumpWidget(MaterialApp(
    home: PedidoPublicoScreen(
      lojaId: lojaId,
      prePedidoId: _pedido,
      repository: PedidoStatusPublicoRepository(db: db),
      itemImageProviderFor: bytes == null
          ? null
          : (url) {
              pedidas.add(url);
              return MemoryImage(bytes);
            },
    ),
  ));
  await tester.pumpAndSettle();
  await _decode(tester);
  return pedidas;
}

Future<void> _decode(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump();
}

void main() {
  group('modelo do espelho público', () {
    test('fromMap aceita só https e toMap omite imagem ausente', () {
      final item = PedidoStatusPublicoItemResumo.fromMap(
          {'nome': 'A', 'quantidade': 1, 'imagem': _imgAnel, 'custo': 9});
      expect(item.toMap(), {'nome': 'A', 'quantidade': 1, 'imagem': _imgAnel});
      for (final bad in [
        'javascript:alert(1)',
        'data:image/png;base64,AA',
        'http://x.com/a.jpg',
        'https://u:p@x.com/a.jpg',
        'https://x.com/"a".jpg',
        '',
        42,
      ]) {
        final m = PedidoStatusPublicoItemResumo.fromMap(
            {'nome': 'A', 'quantidade': 1, 'imagem': bad}).toMap();
        expect(m, {'nome': 'A', 'quantidade': 1}, reason: '$bad');
      }
      expect(publicOrderItemImageUrl(' $_imgAnel '), _imgAnel);
    });

    test('fromPedidoPrivado não publica a imagem do carrinho; copia só do espelho', () {
      final pedido = {
        'status': 'pendente',
        'total': 74.5,
        'itens': [
          {'nome': _nomeEstojo, 'quantidade': 1, 'imagem': 'https://evil.example/a.png', 'imagemSnapshot': 'https://evil.example/a.png'},
          {'nome': _nomeAnel, 'quantidade': 1, 'imagem': _imgEstojo},
        ],
      };
      final sem = PedidoStatusPublico.fromPedidoPrivado(
          pedidoId: _pedido, lojaId: _lojaA, pedidoData: pedido);
      expect(sem.toMap()['itensResumo'], [
        {'nome': _nomeEstojo, 'quantidade': 1},
        {'nome': _nomeAnel, 'quantidade': 1},
      ]);

      final com = PedidoStatusPublico.fromPedidoPrivado(
        pedidoId: _pedido,
        lojaId: _lojaA,
        pedidoData: pedido,
        previousItensResumo: const [
          PedidoStatusPublicoItemResumo(nome: _nomeEstojo, quantidade: 1, imagem: _imgEstojo),
          PedidoStatusPublicoItemResumo(nome: 'Outro', quantidade: 1, imagem: _imgAnel),
        ],
      );
      expect(com.toMap()['itensResumo'], [
        {'nome': _nomeEstojo, 'quantidade': 1, 'imagem': _imgEstojo},
        {'nome': _nomeAnel, 'quantidade': 1},
      ]);
    });

    test('cancelamento pelo app mantém as fotos, o total e muda só o status', () async {
      final db = await _db(_lojaA, _mirror(_lojaA, _doisProdutos));
      await PedidoStatusPublicoRepository(db: db).saveFromPedidoPrivado(
        lojaId: _lojaA,
        pedidoId: _pedido,
        pedidoData: {
          'status': 'pendente',
          'total': 74.5,
          'itens': [
            {'nome': _nomeEstojo, 'quantidade': 1, 'imagem': 'https://evil.example/x.png'},
            {'nome': _nomeAnel, 'quantidade': 1},
          ],
        },
        overrideStatus: 'cancelado',
      );
      final doc = (await db.doc('lojas/$_lojaA/pedido_status_publico/$_pedido').get()).data()!;
      expect(doc['status'], 'cancelado');
      expect(doc['total'], 74.5);
      expect(doc['itensResumo'], _doisProdutos);
    });
  });

  group('página pública do pedido', () {
    testWidgets('dois produtos: cada item mostra a sua foto; total e status iguais',
        (tester) async {
      final db = await _db(_lojaA, _mirror(_lojaA, _doisProdutos));
      final pedidas = await _pump(tester, db, bytes: _png1x1);
      expect(pedidas.toSet(), {_imgEstojo, _imgAnel});
      expect(find.text(_nomeEstojo), findsOneWidget);
      expect(find.text(_nomeAnel), findsOneWidget);
      expect(find.text('1x item(ns)'), findsNWidgets(2));
      expect(find.byType(PublicOrderItemThumbnail), findsNWidgets(2));
      expect(_placeholder, findsNothing);
      expect(find.byType(RawImage), findsNWidgets(2));
      expect(find.text('R\$ 74,50'), findsOneWidget);
      expect(find.text('Aguardando Confirmação'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('um produto com foto', (tester) async {
      final db = await _db(_lojaA, _mirror(_lojaA, [_doisProdutos.last], total: 34.6));
      final pedidas = await _pump(tester, db, bytes: _png1x1);
      expect(pedidas, [_imgAnel]);
      expect(_placeholder, findsNothing);
      expect(find.text('R\$ 34,60'), findsOneWidget);
    });

    testWidgets('pedido antigo sem imagem: placeholder, sem erro e sem pedir imagem',
        (tester) async {
      final db = await _db(_lojaA, _mirror(_lojaA, [
        {'nome': 'Anel', 'quantidade': 1},
      ], total: 10));
      final pedidas = await _pump(tester, db, bytes: _png1x1);
      expect(pedidas, isEmpty);
      expect(find.text('Anel'), findsOneWidget);
      expect(_placeholder, findsOneWidget);
      expect(find.byIcon(Icons.shopping_bag), findsWidgets);
      expect(find.byIcon(Icons.broken_image), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('imagem inválida/indisponível: volta ao placeholder sem exceção',
        (tester) async {
      final db = await _db(_lojaA, _mirror(_lojaA, _doisProdutos));
      await _pump(tester, db, bytes: _invalidBytes);
      expect(_placeholder, findsNWidgets(2));
      expect(find.byIcon(Icons.broken_image), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('URL de rede que falha (NetworkImage real do teste: HTTP 400): placeholder',
        (tester) async {
      final db = await _db(_lojaA, _mirror(_lojaA, [_doisProdutos.first]));
      await _pump(tester, db);
      expect(find.byType(Image), findsOneWidget);
      expect(_placeholder, findsOneWidget);
      expect(find.text(_nomeEstojo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('URL insegura no espelho não é carregada', (tester) async {
      final db = await _db(_lojaA, _mirror(_lojaA, [
        {'nome': 'A', 'quantidade': 1, 'imagem': 'javascript:alert(1)'},
        {'nome': 'B', 'quantidade': 1, 'imagem': 'http://x.com/a.jpg'},
        {'nome': 'C', 'quantidade': 1, 'imagem': 'data:image/png;base64,AA'},
      ]));
      final pedidas = await _pump(tester, db, bytes: _png1x1);
      expect(pedidas, isEmpty);
      expect(_placeholder, findsNWidgets(3));
    });

    testWidgets('outra loja na URL: o pedido (e a foto) não aparece', (tester) async {
      final db = await _db(_lojaB, _mirror(_lojaB, _doisProdutos));
      final pedidas = await _pump(tester, db, lojaId: _lojaA, bytes: _png1x1);
      expect(pedidas, isEmpty);
      expect(find.text(PedidoPublicoScreen.mensagemNaoEncontrado), findsOneWidget);
      expect(find.text(_nomeAnel), findsNothing);
    });

    testWidgets('foto vem só do espelho: sem docs de produto na base, a foto aparece',
        (tester) async {
      final db = await _db(_lojaA, _mirror(_lojaA, _doisProdutos));
      final pedidas = await _pump(tester, db, bytes: _png1x1);
      expect(pedidas.length, 2);
      final colecoes = (await db.collection('lojas/$_lojaA/produtos').get()).docs;
      expect(colecoes, isEmpty);
    });

    for (final (largura, altura) in [
      (320.0, 640.0),
      (360.0, 740.0),
      (390.0, 844.0),
      (412.0, 915.0),
      (768.0, 1024.0),
      (1366.0, 768.0),
    ]) {
      testWidgets('layout ${largura.toInt()}px: nome longo quebra, foto 72px, sem overflow',
          (tester) async {
        tester.view.physicalSize = Size(largura, altura);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const longo = '$_nomeEstojo com nome muito comprido para testar a quebra de linha';
        final db = await _db(_lojaA, _mirror(_lojaA, [
          {'nome': longo, 'quantidade': 3, 'imagem': _imgEstojo},
          {'nome': _nomeAnel, 'quantidade': 1, 'imagem': _imgAnel},
        ]));
        await _pump(tester, db, bytes: _png1x1);
        expect(tester.takeException(), isNull);

        for (final thumb in tester.widgetList<PublicOrderItemThumbnail>(
            find.byType(PublicOrderItemThumbnail))) {
          final size = tester.getSize(find.byWidget(thumb));
          expect(size, const Size(72, 72));
        }
        final nome = find.text(longo);
        final linha = tester.getSize(find.text(_nomeAnel)).height;
        expect(tester.getSize(nome).height, greaterThan(linha));
        expect(tester.getRect(nome).right, lessThanOrEqualTo(largura));
        expect(tester.getSize(nome).width, greaterThan(100));
        expect(find.text('3x item(ns)'), findsOneWidget);
      });
    }
  });

  group('sem regressões', () {
    test('a página e a miniatura não consultam produtos nem inventário', () {
      for (final path in [
        'lib/screens/pedido_publico_screen.dart',
        'lib/widgets/public_order_item_thumbnail.dart',
        'lib/catalog/public_order_item_image.dart',
      ]) {
        final src = File(path).readAsStringSync();
        final codigo = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        final ativo = codigo.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
        for (final proibido in [
          "'produtos'",
          'estoque_produtos',
          'draft_produtos',
          'FirebaseStorage',
          'FirebaseFirestore.instance',
        ]) {
          expect(ativo.contains(proibido), isFalse, reason: '$path: $proibido');
        }
      }
    });

    test('mensagem e link do WhatsApp não mudam com imagem nos itens', () {
      final msg = PrePedidoService.formatarParaWhatsApp(
        prePedido: {
          'id': _pedido,
          'itens': [
            {'nome': _nomeAnel, 'quantidade': 1, 'precoUnitario': 34.6, 'imagem': _imgAnel, 'imagemSnapshot': _imgAnel},
          ],
          'total': 34.6,
          'pagamento': 'pix',
        },
        lojaId: 'nathy-pratas-e-folheados',
      );
      expect(msg, contains('🔗 Ver pedido: https://app.mastepalm.com.br/pedido/$_pedido?loja=nathy-pratas-e-folheados'));
      expect(msg, isNot(contains('firebasestorage')));
    });
  });
}
