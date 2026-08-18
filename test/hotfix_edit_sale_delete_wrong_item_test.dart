import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/nova_venda_line_identity.dart';
import 'package:master_palm/services/venda_edicao_estoque_diff.dart';

/// Espelha o delete de produção em `NovaVendaModal`: `removeAt(index)` do
/// closure do IconButton, sem guarda de reentrada.
void productionRemoveAtIndex(List<Map<String, dynamic>> lines, int index) {
  lines.removeAt(index);
}

Map<String, dynamic> _line({
  required String tag,
  required String productId,
  required String variant,
  required double price,
  int qty = 1,
  String? lineId,
}) {
  return {
    if (lineId != null) kNovaVendaLineIdKey: lineId,
    'tag': tag,
    'produto': 'Produto X',
    'productId': productId,
    'tamanho': variant,
    'cor': '',
    'preco': price,
    'quantidade': qty,
    'extraValor': '',
    'variacaoExtraResumo': variant,
  };
}

List<Map<String, dynamic>> _abcd() => [
      _line(tag: 'A', productId: 'prod-x', variant: 'P', price: 78),
      _line(tag: 'B', productId: 'prod-x', variant: 'M', price: 99),
      _line(tag: 'C', productId: 'prod-x', variant: 'G', price: 121),
      _line(tag: 'D', productId: 'prod-y', variant: '', price: 137),
    ];

String _tags(List<Map<String, dynamic>> lines) =>
    lines.map((e) => e['tag']).join(',');

void main() {
  group('BUG repro — identidade ambígua da produção', () {
    test('removeWhere(productId) apaga TODAS as linhas do mesmo produto', () {
      final lines = _abcd();
      lines.removeWhere((m) => m['productId'] == 'prod-x');
      expect(_tags(lines), 'D');
      expect(lines.length, 1);
    });

    test(
      'removeAt(index) duas vezes (double tap / callback stale) remove a irmã',
      () {
        final lines = _abcd();
        productionRemoveAtIndex(lines, 1);
        productionRemoveAtIndex(lines, 1);
        expect(
          _tags(lines),
          isNot('A,C,D'),
          reason: 'Segundo removeAt(1) apaga C, que o usuário não escolheu',
        );
        expect(_tags(lines), 'A,D');
      },
    );

    test('Map regular usa identidade em == (não é o vetor do bug de conteúdo)',
        () {
      final a = _line(
        tag: 'DUP',
        productId: 'prod-x',
        variant: 'M',
        price: 99,
      );
      final b = _line(
        tag: 'DUP',
        productId: 'prod-x',
        variant: 'M',
        price: 99,
      );
      expect(a == b, isFalse);
      expect(identical(a, b), isFalse);
      final lines = [a, b];
      lines.remove(b);
      expect(identical(lines.single, a), isTrue);
    });
  });

  group('Patch — remove a linha exata', () {
    List<Map<String, dynamic>> fixture() {
      final lines = _abcd();
      ensureNovaVendaLineIds(lines);
      return lines;
    }

    test('delete B: A,C,D permanecem (mesmo productId em A/B/C)', () {
      final lines = fixture();
      final bId = novaVendaLineIdOf(lines[1])!;
      expect(removeExactNovaVendaLine(lines, lineId: bId), isTrue);
      expect(_tags(lines), 'A,C,D');
      expect(lines.map((e) => e['preco']), [78.0, 121.0, 137.0]);
    });

    test('DELETE_FIRST_EXACT_LINE', () {
      final lines = fixture();
      final aId = novaVendaLineIdOf(lines[0])!;
      expect(removeExactNovaVendaLine(lines, lineId: aId), isTrue);
      expect(_tags(lines), 'B,C,D');
    });

    test('DELETE_MIDDLE_EXACT_LINE', () {
      final lines = fixture();
      final bId = novaVendaLineIdOf(lines[1])!;
      expect(removeExactNovaVendaLine(lines, lineId: bId), isTrue);
      expect(_tags(lines), 'A,C,D');
    });

    test('DELETE_LAST_EXACT_LINE', () {
      final lines = fixture();
      final dId = novaVendaLineIdOf(lines[3])!;
      expect(removeExactNovaVendaLine(lines, lineId: dId), isTrue);
      expect(_tags(lines), 'A,B,C');
    });

    test('linhas idênticas: excluir a segunda preserva a primeira', () {
      final a = _line(tag: 'A', productId: 'prod-x', variant: 'M', price: 99);
      final b = _line(tag: 'A', productId: 'prod-x', variant: 'M', price: 99);
      a['tag'] = 'FIRST';
      b['tag'] = 'SECOND';
      final lines = [a, b];
      ensureNovaVendaLineIds(lines);
      final secondId = novaVendaLineIdOf(b)!;
      expect(removeExactNovaVendaLine(lines, lineId: secondId), isTrue);
      expect(lines.length, 1);
      expect(lines.single['tag'], 'FIRST');
      expect(identical(lines.single, a), isTrue);
    });

    test('delete 1 de 3 duplicatas não apaga as outras', () {
      final lines = [
        _line(tag: 'A', productId: 'prod-x', variant: 'P', price: 78),
        _line(tag: 'B', productId: 'prod-x', variant: 'M', price: 99),
        _line(tag: 'C', productId: 'prod-x', variant: 'G', price: 121),
      ];
      ensureNovaVendaLineIds(lines);
      final bId = novaVendaLineIdOf(lines[1])!;
      removeExactNovaVendaLine(lines, lineId: bId);
      expect(lines.length, 2);
      expect(_tags(lines), 'A,C');
    });

    test('excluir uma linha não muta quantidade da irmã', () {
      final lines = [
        _line(tag: 'A', productId: 'prod-x', variant: 'P', price: 78, qty: 3),
        _line(tag: 'B', productId: 'prod-x', variant: 'M', price: 99, qty: 1),
      ];
      ensureNovaVendaLineIds(lines);
      final bId = novaVendaLineIdOf(lines[1])!;
      removeExactNovaVendaLine(lines, lineId: bId);
      expect(lines.single['quantidade'], 3);
      expect(lines.single['tag'], 'A');
    });

    test('double tap no mesmo lineId não remove a segunda linha', () {
      final lines = fixture();
      final bId = novaVendaLineIdOf(lines[1])!;
      expect(removeExactNovaVendaLine(lines, lineId: bId), isTrue);
      expect(removeExactNovaVendaLine(lines, lineId: bId), isFalse);
      expect(_tags(lines), 'A,C,D');
    });

    test('editar irmã e depois excluir B ainda acerta a instância', () {
      final lines = fixture();
      lines[0]['quantidade'] = 5;
      lines[0]['preco'] = 80.0;
      final bId = novaVendaLineIdOf(lines[1])!;
      expect(removeExactNovaVendaLine(lines, lineId: bId), isTrue);
      expect(_tags(lines), 'A,C,D');
      expect(lines[0]['quantidade'], 5);
      expect(lines[0]['preco'], 80.0);
    });

    test('fallback identical() quando lineId falta (venda legado na UI)', () {
      final lines = _abcd();
      final b = lines[1];
      expect(removeExactNovaVendaLine(lines, instance: b), isTrue);
      expect(_tags(lines), 'A,C,D');
    });
  });

  group('Totais após remover B', () {
    test('subtotal/desconto/frete/total coerentes com a regra atual', () {
      final lines = _abcd();
      ensureNovaVendaLineIds(lines);
      final bId = novaVendaLineIdOf(lines[1])!;
      removeExactNovaVendaLine(lines, lineId: bId);

      final subtotal = novaVendaSubtotalOf(lines);
      expect(subtotal, 78 + 121 + 137);

      const frete = 10.0;
      const descontoPct = 10.0;
      final descontoValor = novaVendaDescontoValor(
        subtotal: subtotal,
        desconto: descontoPct,
        descontoEmReais: false,
      );
      final total = novaVendaTotalOf(
        subtotal: subtotal,
        descontoValor: descontoValor,
        frete: frete,
      );
      expect(descontoValor, closeTo(subtotal * 0.10, 0.001));
      expect(total, closeTo(subtotal - descontoValor + frete, 0.001));
    });

    test('pagamentos e troco não são mutados pela exclusão da linha', () {
      final pagamentos = [
        {'forma': 'Dinheiro', 'valor': 200.0},
        {'forma': 'Pix', 'valor': 50.0},
      ];
      const valorRecebidoDinheiro = 250.0;
      final pagamentosAntes =
          pagamentos.map((e) => Map<String, dynamic>.from(e)).toList();

      final lines = _abcd();
      ensureNovaVendaLineIds(lines);
      removeExactNovaVendaLine(
        lines,
        lineId: novaVendaLineIdOf(lines[1]),
      );

      expect(pagamentos, pagamentosAntes);
      final troco = valorRecebidoDinheiro - (pagamentos[0]['valor'] as double);
      expect(troco, 50.0);
    });
  });

  group('Estoque — só a variação realmente removida', () {
    test('remove B (M) devolve só M; P e G inalterados', () {
      final delta = VendaEdicaoEstoqueDiff.calcularDelta(
        linhasAntigas: [
          {
            'productId': 'prod-x',
            'nome': 'Produto X',
            'quantidade': 1,
            'tamanho': 'P',
            'cor': '',
            'extraValor': '',
          },
          {
            'productId': 'prod-x',
            'nome': 'Produto X',
            'quantidade': 1,
            'tamanho': 'M',
            'cor': '',
            'extraValor': '',
          },
          {
            'productId': 'prod-x',
            'nome': 'Produto X',
            'quantidade': 1,
            'tamanho': 'G',
            'cor': '',
            'extraValor': '',
          },
          {
            'productId': 'prod-y',
            'nome': 'Produto Y',
            'quantidade': 1,
            'tamanho': '',
            'cor': '',
            'extraValor': '',
          },
        ],
        linhasNovas: [
          {
            'productId': 'prod-x',
            'nome': 'Produto X',
            'quantidade': 1,
            'tamanho': 'P',
            'cor': '',
            'extraValor': '',
          },
          {
            'productId': 'prod-x',
            'nome': 'Produto X',
            'quantidade': 1,
            'tamanho': 'G',
            'cor': '',
            'extraValor': '',
          },
          {
            'productId': 'prod-y',
            'nome': 'Produto Y',
            'quantidade': 1,
            'tamanho': '',
            'cor': '',
            'extraValor': '',
          },
        ],
      );
      expect(delta.baixar, isEmpty);
      expect(delta.devolver.length, 1);
      expect(delta.devolver.single['tamanho'], 'M');
      expect(delta.devolver.single['productId'], 'prod-x');
      expect(delta.devolver.single['quantidade'], 1);
    });
  });

  group('Persistência simulada (reload)', () {
    test('após delete B, lista recarregada preserva A,C,D na ordem', () {
      final live = _abcd();
      ensureNovaVendaLineIds(live);
      final bId = novaVendaLineIdOf(live[1])!;
      removeExactNovaVendaLine(live, lineId: bId);

      final persisted = live
          .map(
            (m) => {
              'produto': m['produto'],
              'productId': m['productId'],
              'tamanho': m['tamanho'],
              'preco': m['preco'],
              'quantidade': m['quantidade'],
              'tag': m['tag'],
            },
          )
          .toList();
      expect(persisted.map((e) => e['tag']), ['A', 'C', 'D']);
      expect(persisted.map((e) => e['tamanho']), ['P', 'G', '']);
    });
  });

  group('Widget keys — Autocomplete + índice reusa a linha errada', () {
    testWidgets(
      'ValueKey(index) mantém texto da linha apagada no slot reutilizado',
      (tester) async {
        final labels = ['A-P-78', 'B-M-99', 'C-G-121', 'D-Y-137'];

        await tester.pumpWidget(
          MaterialApp(
            home: _IndexKeyedAutocompleteHost(labels: labels),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('del_1')));
        await tester.pumpAndSettle();

        final remaining = tester
            .widgetList<TextField>(find.byType(TextField))
            .map((f) => f.controller?.text)
            .toList();

        expect(
          remaining,
          isNot(['A-P-78', 'C-G-121', 'D-Y-137']),
          reason:
              'Autocomplete.initialValue + ValueKey(index) reusa o State de B',
        );
        expect(remaining.contains('B-M-99'), isTrue);
      },
    );

    testWidgets(
      'ValueKey(lineId) remonta Autocomplete e mostra as linhas restantes',
      (tester) async {
        final lines = _abcd();
        ensureNovaVendaLineIds(lines);

        await tester.pumpWidget(
          MaterialApp(
            home: _LineIdKeyedAutocompleteHost(lines: lines),
          ),
        );
        await tester.pumpAndSettle();

        final bId = novaVendaLineIdOf(lines[1])!;
        await tester.tap(find.byKey(ValueKey('del_$bId')));
        await tester.pumpAndSettle();

        final remaining = tester
            .widgetList<TextField>(find.byType(TextField))
            .map((f) => f.controller?.text)
            .toList();
        expect(remaining, ['A-P-78', 'C-G-121', 'D-Y-137']);
      },
    );
  });
}

class _IndexKeyedAutocompleteHost extends StatefulWidget {
  const _IndexKeyedAutocompleteHost({required this.labels});
  final List<String> labels;

  @override
  State<_IndexKeyedAutocompleteHost> createState() =>
      _IndexKeyedAutocompleteHostState();
}

class _IndexKeyedAutocompleteHostState
    extends State<_IndexKeyedAutocompleteHost> {
  late List<String> labels = List<String>.from(widget.labels);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          for (var i = 0; i < labels.length; i++)
            Row(
              key: ValueKey('row_$i'),
              children: [
                Expanded(
                  child: Autocomplete<String>(
                    key: ValueKey('dropdown_$i'),
                    initialValue: TextEditingValue(text: labels[i]),
                    optionsBuilder: (v) => const <String>[],
                    fieldViewBuilder:
                        (context, controller, focusNode, onSubmit) {
                      return TextField(controller: controller);
                    },
                  ),
                ),
                IconButton(
                  key: ValueKey('del_$i'),
                  onPressed: () => setState(() => labels.removeAt(i)),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LineIdKeyedAutocompleteHost extends StatefulWidget {
  const _LineIdKeyedAutocompleteHost({required this.lines});
  final List<Map<String, dynamic>> lines;

  @override
  State<_LineIdKeyedAutocompleteHost> createState() =>
      _LineIdKeyedAutocompleteHostState();
}

class _LineIdKeyedAutocompleteHostState
    extends State<_LineIdKeyedAutocompleteHost> {
  late final List<Map<String, dynamic>> lines = widget.lines;

  String _labelOf(Map<String, dynamic> m) =>
      '${m['tag']}-${(m['tamanho'] as String).isEmpty ? 'Y' : m['tamanho']}-${(m['preco'] as num).toInt()}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          for (final item in List<Map<String, dynamic>>.from(lines))
            Row(
              key: novaVendaLineWidgetKey(item, 'row_'),
              children: [
                Expanded(
                  child: Autocomplete<String>(
                    key: novaVendaLineWidgetKey(item, 'dropdown_'),
                    initialValue: TextEditingValue(text: _labelOf(item)),
                    optionsBuilder: (v) => const <String>[],
                    fieldViewBuilder:
                        (context, controller, focusNode, onSubmit) {
                      return TextField(controller: controller);
                    },
                  ),
                ),
                IconButton(
                  key: ValueKey('del_${novaVendaLineIdOf(item)}'),
                  onPressed: () {
                    setState(() {
                      removeExactNovaVendaLine(
                        lines,
                        lineId: novaVendaLineIdOf(item),
                      );
                    });
                  },
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
