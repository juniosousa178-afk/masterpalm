// Regressão estática: garante que strings de contrato / fluxos críticos não somem do código.
// Não substitui testes de integração; evita remoção acidental de guardas.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;

  String read(String rel) =>
      File('$root${Platform.pathSeparator}$rel').readAsStringSync();

  group('Exclusão definitiva de venda + estoque', () {
    test('vendas_service mantém aborto e tags [VENDA_DELETE]', () {
      final s = read('lib/services/vendas_service.dart');
      expect(s.contains('[VENDA_DELETE]'), isTrue);
      expect(s.contains('exclusao_abortada_por_estoque'), isTrue);
      expect(s.contains('Error.throwWithStackTrace'), isTrue);
    });

    test('soft_delete mantém pendência em falha', () {
      final s = read('lib/services/soft_delete_service.dart');
      expect(
        s.contains('exclusão definitiva falhou; pendência mantida'),
        isTrue,
      );
    });
  });

  group('Navegação financeira (mesInicial)', () {
    test('hub financeiro repassa mesInicial ao resumo', () {
      final s = read('lib/screens/financeiro/financeiro_screen.dart');
      expect(s.contains('mesInicial:'), isTrue);
      expect(s.contains('FinanceiroResumoConsolidadoScreen'), isTrue);
    });
  });
}
