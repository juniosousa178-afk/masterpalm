// Garante que checagem de limite ocorre antes de registrarVendaMulti no modal.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/limits_guard.dart';

void main() {
  group('nova_venda_modal — ordem limite antes de salvar', () {
    late String src;

    setUp(() {
      src = File('lib/screens/nova_venda_modal.dart').readAsStringSync();
    });

    test('checkVendaLimit ocorre antes de VendasService.registrarVendaMulti', () {
      final iLimite = src.indexOf('checkVendaLimit(lojaId)');
      final iRegistro = src.indexOf('VendasService.registrarVendaMulti');
      expect(iLimite, greaterThan(-1));
      expect(iRegistro, greaterThan(iLimite));
    });

    test('bloqueio por limite retorna cedo sem chamar registrarVendaMulti', () {
      final fnStart = src.indexOf('Future<(bool, String?, String?)> _salvarVendaEmBackground');
      expect(fnStart, greaterThan(-1));
      final fnSlice = src.substring(fnStart, fnStart + 3500);
      final iLimite = fnSlice.indexOf('checkVendaLimit(lojaId)');
      final iEarlyReturn = fnSlice.indexOf('return (false, null, msg)');
      final iRegistro = fnSlice.indexOf('VendasService.registrarVendaMulti');
      expect(iLimite, greaterThan(-1));
      expect(iEarlyReturn, greaterThan(iLimite));
      expect(iRegistro, greaterThan(iEarlyReturn));
    });

    test('mensagem de limite vem de userMessage(), não hardcoded Free', () {
      expect(src.contains('Limite de vendas do mês atingido no plano Free'), isFalse);
      expect(src.contains('limite.userMessage()'), isTrue);
    });

    test('bloqueio usa canAdd (cobre limite real e falha de consulta)', () {
      expect(src.contains('if (!limite.canAdd)'), isTrue);
      expect(src.contains('canAddVenda(lojaId)'), isFalse);
    });

    test('checkFailed não usa mensagem hardcoded de limite Free', () {
      expect(
        VendaLimitCheckResult(status: VendaLimitStatus.checkFailed).userMessage(),
        isNot(contains('Limite de vendas do mês atingido')),
      );
      expect(
        VendaLimitCheckResult(status: VendaLimitStatus.checkFailed).userMessage(),
        contains('verificar o limite'),
      );
    });
  });
}
