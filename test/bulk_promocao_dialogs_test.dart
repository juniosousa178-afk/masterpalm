import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/bulk_promocao_service.dart';
import 'package:master_palm/widgets/bulk_promocao_dialogs.dart';

const sizes = {
  '360px': Size(360, 740),
  'desktop': Size(1440, 900),
};

BulkPromoCandidato c(String id, bool promo) =>
    BulkPromoCandidato(hiveKey: id.hashCode, docId: id, nome: id, lojaId: 'lojaA', emPromocao: promo);

BulkPromoPreview preview() => BulkPromoPreview.calcular([
      for (var i = 0; i < 12; i++) c('com$i', true),
      for (var i = 0; i < 3; i++) c('sem$i', false),
    ]);

Future<List<Object?>> openDialog(WidgetTester tester, Size size, WidgetBuilder builder) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <Object?>[];
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => results.add(await showDialog<Object?>(context: context, builder: builder)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return results;
}

void main() {
  for (final entry in sizes.entries) {
    testWidgets('${entry.key}: confirmação com título, garantias e botões do contrato', (tester) async {
      await openDialog(tester, entry.value, (_) => BulkPromoPreviewDialog(preview: preview()));
      expect(tester.takeException(), isNull);
      expect(find.text('Desativar a promoção de 15 produtos?'), findsOneWidget);
      expect(find.text('12 produtos terão a promoção desativada.'), findsOneWidget);
      expect(find.text('3 já estão sem promoção e não serão alterados.'), findsOneWidget);
      expect(find.text('O preço normal será mantido.'), findsOneWidget);
      expect(find.text('O estoque não será alterado.'), findsOneWidget);
      expect(find.text('Nenhum produto será excluído.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancelar'), findsOneWidget);
      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Desativar promoções'));
      expect(btn.onPressed, isNotNull);
    });
  }

  testWidgets('cancelar não confirma', (tester) async {
    final results = await openDialog(tester, sizes['360px']!, (_) => BulkPromoPreviewDialog(preview: preview()));
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();
    expect(results, [false]);
  });

  testWidgets('confirmação dupla fecha uma única vez', (tester) async {
    final results = await openDialog(tester, sizes['360px']!, (_) => BulkPromoPreviewDialog(preview: preview()));
    final confirm = find.widgetWithText(FilledButton, 'Desativar promoções');
    await tester.tap(confirm);
    await tester.pump();
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(results, [true]);
    expect(find.text('abrir'), findsOneWidget);
  });

  testWidgets('resultado parcial: X / Y / Z e nova tentativa só das falhas', (tester) async {
    final r = BulkPromoResultado(
      desativados: {for (var i = 0; i < 18; i++) 'p$i'},
      jaSemPromocao: 3,
      falhas: const [
        BulkPromoFalha(docId: 'x', mensagem: 'Falha de conexão ao desativar "X"', podeTentarDeNovo: true),
        BulkPromoFalha(docId: 'y', mensagem: '"Y" foi excluído.', podeTentarDeNovo: false),
      ],
    );
    final results = await openDialog(tester, sizes['360px']!, (_) => BulkPromoResultadoDialog(resultado: r));
    expect(tester.takeException(), isNull);
    expect(find.text('Promoções desativadas em parte'), findsOneWidget);
    expect(find.text('18 promoções desativadas'), findsOneWidget);
    expect(find.text('3 já estavam sem promoção'), findsOneWidget);
    expect(find.text('2 falharam'), findsOneWidget);
    expect(r.idsParaNovaTentativa, ['x']);
    await tester.tap(find.widgetWithText(FilledButton, 'Tentar novamente'));
    await tester.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('falhas sem nova tentativa possível: só "Fechar"', (tester) async {
    final r = BulkPromoResultado(desativados: const {}, jaSemPromocao: 0, falhas: const [
      BulkPromoFalha(docId: 'y', mensagem: 'sem permissão', podeTentarDeNovo: false),
    ]);
    await openDialog(tester, sizes['desktop']!, (_) => BulkPromoResultadoDialog(resultado: r));
    expect(find.text('Promoções não desativadas'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Tentar novamente'), findsNothing);
  });

  testWidgets('selo "Promoção" some quando a promoção é desativada', (tester) async {
    final emPromocao = ValueNotifier(true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: emPromocao,
          builder: (_, v, __) => Row(children: [
            const Text('Terço'),
            Flexible(child: ProdutoPromocaoBadge(emPromocao: v)),
          ]),
        ),
      ),
    ));
    expect(find.text('Promoção'), findsOneWidget);
    emPromocao.value = false;
    await tester.pump();
    expect(find.text('Promoção'), findsNothing);
    expect(find.text('Terço'), findsOneWidget);
  });
}
