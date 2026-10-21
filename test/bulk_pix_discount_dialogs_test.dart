import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/bulk_pix_discount_service.dart';
import 'package:master_palm/widgets/bulk_pix_discount_dialogs.dart';

const sizes = {
  '360px': Size(360, 740),
  '390px': Size(390, 844),
  'tablet': Size(820, 1180),
  'desktop': Size(1440, 900),
};

BulkPixPreview preview20() => BulkPixPreview.calcular(
      [
        for (var i = 0; i < 16; i++)
          BulkPixCandidato(hiveKey: i, docId: 'com$i', nome: 'Produto $i', percentualDescontoPix: 10),
        for (var i = 0; i < 4; i++)
          BulkPixCandidato(hiveKey: 100 + i, docId: 'sem$i', nome: 'Sem $i', percentualDescontoPix: 0),
        const BulkPixCandidato(hiveKey: 999, docId: '', nome: 'Local', percentualDescontoPix: 5),
      ],
      foraDoFiltro: 3,
    );

BulkPixResultado parcial() => BulkPixResultado(
      solicitados: 35,
      atualizados: {for (var i = 30; i < 35; i++) 'p$i'},
      semAlteracao: const {},
      falhas: [
        BulkPixFalhaLote(
          productIds: [for (var i = 0; i < 30; i++) 'p$i'],
          mensagem: '"Colar de Prata com Pingente de Coração Cravejado" não foi encontrado na nuvem. '
              'Nenhum produto deste lote foi alterado.',
          productIdIndisponivel: 'p5',
        ),
      ],
    );

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
    group('${entry.key} (§26)', () {
      testWidgets('preview cabe e mostra contagens', (tester) async {
        await openDialog(tester, entry.value, (_) => BulkPixPreviewDialog(preview: preview20()));
        expect(tester.takeException(), isNull);
        expect(find.text('Remover desconto no Pix de 21 produtos?'), findsOneWidget);
        expect(find.text('16 produtos terão o desconto no Pix removido.'), findsOneWidget);
        expect(find.text('4 já estão sem desconto e não serão alterados.'), findsOneWidget);
        final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Remover desconto no Pix'));
        expect(btn.onPressed, isNotNull);
      });

      testWidgets('progresso cabe', (tester) async {
        final progresso = ValueNotifier('Removendo desconto no Pix… 30 de 61');
        await openDialog(tester, entry.value, (_) => BulkPixProgressDialog(progresso: progresso));
        expect(tester.takeException(), isNull);
        expect(find.text('Removendo desconto no Pix… 30 de 61'), findsOneWidget);
      });

      testWidgets('resumo parcial cabe', (tester) async {
        await openDialog(tester, entry.value, (_) => BulkPixResultadoDialog(resultado: parcial()));
        expect(tester.takeException(), isNull);
        expect(find.text('Desconto no Pix removido em parte'), findsOneWidget);
        expect(find.text('5 produtos atualizados'), findsOneWidget);
        expect(find.text('30 falhas'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Tentar novamente'), findsOneWidget);
      });
    });
  }

  testWidgets('confirmação dupla fecha o diálogo uma única vez (§20)', (tester) async {
    final results = await openDialog(tester, sizes['390px']!, (_) => BulkPixPreviewDialog(preview: preview20()));
    final confirm = find.widgetWithText(FilledButton, 'Remover desconto no Pix');
    await tester.tap(confirm);
    await tester.pump();
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(results, [true]);
    expect(find.text('abrir'), findsOneWidget, reason: 'underlying screen not popped');
  });

  testWidgets('nada sincronizado: confirmação desabilitada', (tester) async {
    final p = BulkPixPreview.calcular(
        [const BulkPixCandidato(hiveKey: 1, docId: '', nome: 'x', percentualDescontoPix: 5)]);
    await openDialog(tester, sizes['360px']!, (_) => BulkPixPreviewDialog(preview: p));
    final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Remover desconto no Pix'));
    expect(btn.onPressed, isNull);
  });

  testWidgets('progresso não fecha com voltar (§20)', (tester) async {
    final progresso = ValueNotifier('Removendo desconto no Pix… 0 de 3');
    await openDialog(tester, sizes['360px']!, (_) => BulkPixProgressDialog(progresso: progresso));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BulkPixProgressDialog), findsOneWidget);
    progresso.value = 'Removendo desconto no Pix… 3 de 3';
    await tester.pump();
    expect(find.text('Removendo desconto no Pix… 3 de 3'), findsOneWidget);
  });

  testWidgets('sucesso total: sem botão de nova tentativa', (tester) async {
    final ok = BulkPixResultado(solicitados: 3, atualizados: {'A', 'B'}, semAlteracao: {'C'}, falhas: const []);
    await openDialog(tester, sizes['desktop']!, (_) => BulkPixResultadoDialog(resultado: ok));
    expect(find.text('Desconto no Pix removido'), findsOneWidget);
    expect(find.text('2 produtos atualizados'), findsOneWidget);
    expect(find.text('1 já estava sem desconto'), findsOneWidget);
    expect(find.text('0 falhas'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Tentar novamente'), findsNothing);
  });
}
