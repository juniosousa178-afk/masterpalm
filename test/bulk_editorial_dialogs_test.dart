import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/bulk_editorial_service.dart';
import 'package:master_palm/widgets/bulk_editorial_dialogs.dart';

BulkEditorialResultado _resultado({
  Set<String> confirmados = const {},
  List<BulkEditorialFalha> falhas = const [],
  int ignorados = 0,
}) =>
    BulkEditorialResultado(
      plano: BulkEditorialPlano.descontoPix(10),
      totalSelecionados: confirmados.length + falhas.length + ignorados,
      confirmados: confirmados,
      ignorados: ignorados,
      falhas: falhas,
    );

Future<void> _pump(WidgetTester tester, BulkEditorialResultado r) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: BulkEditorialResultadoDialog(resultado: r))),
    );

void main() {
  testWidgets('parcial com falha recuperável: contagens reais e botão de nova tentativa', (tester) async {
    await _pump(
      tester,
      _resultado(confirmados: {'a', 'b'}, falhas: const [
        BulkEditorialFalha(docId: 'c', mensagem: 'Falha de conexão ao atualizar "C"', podeTentarDeNovo: true),
      ]),
    );
    expect(find.text('Desconto no Pix: aplicado em parte'), findsOneWidget);
    expect(find.text('2 produtos atualizados'), findsOneWidget);
    expect(find.text('1 falhou'), findsOneWidget);
    expect(find.textContaining('Falha de conexão'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('tudo falhou sem falha recuperável: sem sucesso e sem nova tentativa', (tester) async {
    await _pump(
      tester,
      _resultado(falhas: const [
        BulkEditorialFalha(docId: 'a', mensagem: 'Sem permissão', podeTentarDeNovo: false),
      ]),
    );
    expect(find.text('Desconto no Pix: nada foi aplicado'), findsOneWidget);
    expect(find.text('0 produtos atualizados'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsNothing);
  });

  testWidgets('confirmados + ignorados: informa os não sincronizados', (tester) async {
    await _pump(tester, _resultado(confirmados: {'a'}, ignorados: 2));
    expect(find.text('Desconto no Pix aplicado'), findsOneWidget);
    expect(find.text('1 produto atualizado'), findsOneWidget);
    expect(find.textContaining('2 produtos ainda não foram sincronizados'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsNothing);
  });
}
