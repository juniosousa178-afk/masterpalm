import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/roleta_catalogo_service.dart';

void main() {
  group('resolvePremioVisualIndex', () {
    final segmentos = <Map<String, dynamic>>[
      {'label': 'Brinde', 'tipo': 'brinde', 'valor': 0.0},
      {'label': '5% OFF', 'tipo': 'desconto', 'valor': 5.0},
      {'label': '10% OFF', 'tipo': 'desconto', 'valor': 10.0},
      {'label': 'Frete grátis', 'tipo': 'frete_gratis', 'valor': 0.0},
    ];

    test('usa premioIndex retornado pela Function quando válido', () {
      final index = resolvePremioVisualIndex(
        segmentos: segmentos,
        premioIndex: 2,
        premio: {'label': '10% OFF', 'tipo': 'desconto', 'valor': 10.0},
      );

      expect(index, 2);
    });

    test('faz fallback por tipo+valor+label quando premioIndex não vier', () {
      final index = resolvePremioVisualIndex(
        segmentos: segmentos,
        premio: {'label': 'Brinde', 'tipo': 'brinde', 'valor': 0.0},
      );

      expect(index, 0);
    });

    test('não escolhe setor ambíguo quando há prêmio duplicado sem índice', () {
      final index = resolvePremioVisualIndex(
        segmentos: <Map<String, dynamic>>[
          {'label': 'Brinde', 'tipo': 'brinde', 'valor': 0.0},
          {'label': 'Brinde', 'tipo': 'brinde', 'valor': 0.0},
        ],
        premio: {'label': 'Brinde', 'tipo': 'brinde', 'valor': 0.0},
      );

      expect(index, isNull);
    });
  });

  group('calculateRoletaFinalAngle', () {
    test('alinha o centro visual do prêmio com o ponteiro no topo', () {
      const totalSegmentos = 4;
      const premioIndex = 2;
      const voltasCompletas = 4;

      final finalAngle = calculateRoletaFinalAngle(
        premioIndex: premioIndex,
        totalSegmentos: totalSegmentos,
        voltasCompletas: voltasCompletas,
      );

      final centerAfterRotation = normalizeRoletaAngle(
        roletaSegmentCenterAngle(
              segmentoIndex: premioIndex,
              totalSegmentos: totalSegmentos,
            ) +
            finalAngle,
      );

      expect(
        centerAfterRotation,
        closeTo(normalizeRoletaAngle(-math.pi / 2), 0.000001),
      );
    });

    test('índices diferentes produzem paradas finais diferentes', () {
      final angleBrinde = calculateRoletaFinalAngle(
        premioIndex: 0,
        totalSegmentos: 4,
        voltasCompletas: 4,
      );
      final angleDesconto = calculateRoletaFinalAngle(
        premioIndex: 2,
        totalSegmentos: 4,
        voltasCompletas: 4,
      );

      expect(angleBrinde, isNot(angleDesconto));
    });
  });
}
