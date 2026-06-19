import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';

/// Espelha o layout responsivo de `_barraFiltros` da Gestão Financeira.
class _ListaLancamentosFiltrosMobileTest extends StatefulWidget {
  const _ListaLancamentosFiltrosMobileTest();

  @override
  State<_ListaLancamentosFiltrosMobileTest> createState() =>
      _ListaLancamentosFiltrosMobileTestState();
}

class _ListaLancamentosFiltrosMobileTestState
    extends State<_ListaLancamentosFiltrosMobileTest> {
  bool _visaoCompetencia = false;
  String? _status;
  String? _tipo;

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
  }

  Widget _banner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const textos = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lista por pagamento — alinhada aos KPIs',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, height: 1.25),
              ),
              SizedBox(height: 2),
              Text(
                'Mesmo recorte dos indicadores oficiais',
                style: TextStyle(fontSize: 10, height: 1.2),
              ),
            ],
          );
          if (constraints.maxWidth < 360) {
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.payments_outlined, size: 18),
                SizedBox(height: 6),
                textos,
              ],
            );
          }
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.payments_outlined, size: 18),
              SizedBox(width: 8),
              Expanded(child: textos),
            ],
          );
        },
      ),
    );
  }

  Widget _dropdowns() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final status = DropdownButtonFormField<String?>(
          value: _status,
          isExpanded: true,
          decoration: _decoration('Status'),
          items: const [
            DropdownMenuItem(value: null, child: Text('Todos')),
            DropdownMenuItem(value: 'pago', child: Text('Pago')),
          ],
          onChanged: (v) => setState(() => _status = v),
        );
        final tipo = DropdownButtonFormField<String?>(
          value: _tipo,
          isExpanded: true,
          decoration: _decoration('Tipo / visão'),
          items: const [
            DropdownMenuItem(value: null, child: Text('Todos')),
            DropdownMenuItem(
              value: FinanceiroTipoLancamento.despesaOperacional,
              child: Text('Despesa operacional'),
            ),
          ],
          onChanged: (v) => setState(() => _tipo = v),
        );
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              status,
              const SizedBox(height: 8),
              tipo,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: status),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: tipo),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Lista de lançamentos',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Por pagamento'),
                  selected: !_visaoCompetencia,
                  onSelected: (_) => setState(() => _visaoCompetencia = false),
                ),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Por competência'),
                  selected: _visaoCompetencia,
                  onSelected: (_) => setState(() => _visaoCompetencia = true),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: _banner(),
            ),
            _dropdowns(),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('Lista de lançamentos mobile sem overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: const _ListaLancamentosFiltrosMobileTest(),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Lista de lançamentos'), findsOneWidget);
    expect(find.text('Por pagamento'), findsOneWidget);
    expect(find.text('Por competência'), findsOneWidget);
    expect(find.text('Lista por pagamento — alinhada aos KPIs'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Tipo / visão'), findsOneWidget);
  });
}
