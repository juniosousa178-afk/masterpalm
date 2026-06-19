import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout alinhado ao card da Gestão Financeira (Recebimento — Junho).
class _RecebimentoJunhoCard extends StatelessWidget {
  const _RecebimentoJunhoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 18,
                  child: Icon(Icons.receipt_long, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recebimento — Junho',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Gerado por Conta a Receber',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.indigo.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Entrada extra · Finalizado · Jun/2026',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.25),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'R\$ 8,00',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () {},
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('Recebimento — Junho card mobile sem overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: const _RecebimentoJunhoCard(),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Recebimento — Junho'), findsOneWidget);
    expect(find.text('Gerado por Conta a Receber'), findsOneWidget);
    expect(find.text('R\$ 8,00'), findsOneWidget);
  });
}
