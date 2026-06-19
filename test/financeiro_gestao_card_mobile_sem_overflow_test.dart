import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _GestaoLancamentoCardTest extends StatelessWidget {
  const _GestaoLancamentoCardTest();

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
                const CircleAvatar(radius: 18, child: Icon(Icons.receipt_long, size: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Recebimento — Junho', maxLines: 2),
                      Text(
                        'Gerado por Conta a Receber',
                        style: TextStyle(fontSize: 10, color: Colors.indigo.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(child: Text('R\$ 8,00', style: TextStyle(fontWeight: FontWeight.bold))),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () {},
                  icon: const Icon(Icons.delete_outline, size: 20),
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
  testWidgets('card mobile estreito sem overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: const _GestaoLancamentoCardTest(),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
