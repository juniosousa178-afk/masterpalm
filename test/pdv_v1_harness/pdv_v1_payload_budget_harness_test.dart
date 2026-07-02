import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'support/pdv_v1_payload_metrics.dart';

void main() {
  group('PDV V1 — payload budget harness (sintético)', () {
    late List<Map<String, dynamic>> reports;

    setUp(() {
      reports = [];
    });

    void measure(String label, int items,
        {bool variacoes = false, bool combo = false, bool fiado = false}) {
      final snap = pdvV1SyntheticPreparedSnapshot(
        itemCount: items,
        withVariacoes: variacoes,
        withCombo: combo,
        withFiado: fiado,
      );
      final tx = pdvV1SyntheticTxItems(items);
      reports.add(
        pdvV1MeasurePayload(
          label: label,
          preparedSnapshot: snap,
          txItems: tx,
        ).toMap(),
      );
    }

    test('registra payload de cenários sintéticos obrigatórios', () {
      measure('venda_simples_3', 3);
      measure('variacoes_5', 5, variacoes: true);
      measure('combo_8', 8, combo: true);
      measure('fiado_4', 4, fiado: true);
      measure('limite_app_150', 150);

      expect(reports.length, 5);
      for (final r in reports) {
        expect(r['preparedSnapshotBytes'], greaterThan(0));
        expect(r['plannedWrites'], greaterThan(0));
      }

      final limite150 = reports.last;
      expect(limite150['mergedItemCount'], 150);
      expect(limite150['plannedReads'], 151); // 1 marcador + 150 docs
      expect(limite150['plannedWrites'], 451); // 150*3 + 1 marcador
    });

    test('produto com mapas grandes de variação — tamanho doc estimado', () {
      final large = pdvV1SyntheticLargeVariationProduct();
      final bytes = utf8.encode(jsonEncode(large)).length;
      // Documento Firestore max 1 MiB — apenas estimativa JSON local.
      expect(bytes, greaterThan(5000));
      expect(bytes, lessThan(1048576),
          reason:
              'Harness: JSON sintético abaixo de 1 MiB; wire pode diferir.');
    });

    test('limitações explícitas do harness', () {
      expect(
        true,
        isTrue,
        reason:
            'JSON UTF-8 ≠ tamanho wire do commit; latência local ≠ produção; '
            'emulator ≠ quota/contention real; cap V1 NÃO definido aqui.',
      );
    });
  });
}
