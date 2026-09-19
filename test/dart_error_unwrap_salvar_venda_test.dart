import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
import 'package:master_palm/core/nova_venda_payment_guard.dart';
class _FakeConvertedFutureError implements Exception {
  _FakeConvertedFutureError(this.error);
  final Object error;

  @override
  String toString() =>
      "Error: Dart exception thrown from converted Future. "
      "Use the properties 'error' to fetch the boxed error and 'stack' to recover the stack trace.";
}

void main() {
  group('formatDartErrorForUser — interop web', () {
    test('não expõe converted Future quando há erro interno', () {
      const inner = 'Estoque insuficiente para "Anel". Disponível: 0, solicitado: 1.';
      final wrapped = _FakeConvertedFutureError(Exception(inner));

      expect(formatDartErrorForUser(wrapped), contains('Estoque insuficiente'));
      expect(formatDartErrorForUser(wrapped), isNot(contains('converted Future')));
    });

    test('wrapper sem erro interno vira mensagem genérica segura', () {
      final wrapped = _FakeConvertedFutureError(Object());

      expect(formatDartErrorForUser(wrapped), isNot(contains('converted Future')));
      expect(formatDartErrorForUser(wrapped), contains('Falha na operação'));
    });
  });

  group('formatSalvarVendaErrorForUser', () {
    test('classifica estoque insuficiente', () {
      final msg = formatSalvarVendaErrorForUser(
        Exception('Estoque insuficiente para "Pingente". Disponível: 1, solicitado: 3.'),
      );
      expect(msg.toLowerCase(), contains('estoque'));
      expect(msg.toLowerCase(), isNot(contains('conexão')));
      expect(msg, isNot(contains('converted Future')));
    });

    FirebaseFunctionsException fn(String code, String message) =>
        FirebaseFunctionsException(code: code, message: message);

    test('estoque zero não vira falha de conexão', () {
      final msg = formatSalvarVendaErrorForUser(
        fn('failed-precondition', 'Invalid canonical stock quantity'),
      );
      expect(msg, 'Sem estoque disponível para esta variação.');
      expect(msg.toLowerCase(), isNot(contains('conexão')));
    });

    test('variation not found não vira falha de conexão', () {
      final msg = formatSalvarVendaErrorForUser(
        fn('failed-precondition', 'Variation not found'),
      );
      expect(msg, 'Variação não encontrada para este produto.');
      expect(msg.toLowerCase(), isNot(contains('conexão')));
    });

    test('produto sem grant não vira falha de conexão', () {
      final msg = formatSalvarVendaErrorForUser(
        fn('permission-denied', 'VARIATION_SALE_PRODUCT_NOT_AUTHORIZED'),
      );
      expect(msg, 'Este produto não está autorizado para venda com variação.');
      expect(msg.toLowerCase(), isNot(contains('conexão')));
    });

    test('produto unsafe/grade não vira falha de conexão', () {
      final msg = formatSalvarVendaErrorForUser(
        fn('permission-denied', 'GRADE_SALE_NOT_AUTHORIZED'),
      );
      expect(msg, contains('grade extra'));
      expect(msg.toLowerCase(), isNot(contains('conexão')));
    });

    test('CAS/revision conflict não vira falha de conexão', () {
      final msg = formatSalvarVendaErrorForUser(
        fn('aborted', 'Stock revision conflict'),
      );
      expect(msg.toLowerCase(), contains('estoque foi atualizado'));
      expect(msg.toLowerCase(), isNot(contains('conexão')));
    });

    test('rede realmente offline continua falha de conexão', () {
      final msg = formatSalvarVendaErrorForUser(
        fn('unavailable', 'UNAVAILABLE'),
      );
      expect(msg, contains('Falha de conexão ao salvar a venda'));
    });

    test('backend 500 não vira falha de conexão', () {
      final msg = formatSalvarVendaErrorForUser(
        fn('internal', 'INTERNAL'),
      );
      expect(msg.toLowerCase(), contains('servidor'));
      expect(msg.toLowerCase(), isNot(contains('conexão')));
    });

    test('dependency migration / conferência não vira falha de conexão', () {
      final msg = formatSalvarVendaErrorForUser(
        fn('failed-precondition', 'Dependency migration required'),
      );
      expect(msg, 'Este produto precisa de conferência de estoque antes da venda.');
      expect(msg.toLowerCase(), isNot(contains('conexão')));
    });

    test('pagamento incompleto tem mensagem específica', () {
      final msg = formatSalvarVendaErrorForUser(
        Exception('O valor pago (R\$ 0.00) não bate com o total (R\$ 10.00).'),
      );
      expect(msg, kNovaVendaPagamentoIncompletoMensagem);
    });

    test('classifica Firebase permission-denied sem expor code/plugin', () {
      final msg = formatSalvarVendaErrorForUser(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        ),
      );
      expect(msg.toLowerCase(), contains('permiss'));
      expect(msg, isNot(contains('code=')));
      expect(msg, isNot(contains('plugin=')));
      expect(msg, isNot(contains('converted Future')));
    });

    test('preserva erro de sincronização/nuvem', () {
      final msg = formatSalvarVendaErrorForUser(
        Exception(
          'Produto não encontrado no estoque da nuvem (ID abc). '
          'Sincronize antes de finalizar a venda.',
        ),
      );
      expect(msg.toLowerCase(), contains('nuvem'));
    });

    test('mensagem final não contém artefatos técnicos web', () {
      const inner = 'Estoque insuficiente para "Anel". Disponível: 0, solicitado: 1.';
      final wrapped = _FakeConvertedFutureError(Exception(inner));
      final msg = formatSalvarVendaErrorForUser(wrapped);

      for (final forbidden in [
        'converted Future',
        'Instance of',
        '.error',
        '.stack',
        'code=',
        'plugin=',
        'lojas/',
      ]) {
        expect(msg.contains(forbidden), isFalse, reason: 'contém $forbidden');
      }
    });
  });

  group('nova_venda_modal — formatter na finalização', () {
    late String src;

    setUp(() {
      src = File('lib/screens/nova_venda_modal.dart').readAsStringSync();
    });

    test('catch UI_FINALIZAR usa formatSalvarVendaErrorForUser', () {
      expect(src.contains('formatSalvarVendaErrorForUser(e)'), isTrue);
      expect(
        src.contains('Detalhe: \${_detalharErroSalvarVenda(e)}'),
        isFalse,
      );
    });

    test('_salvarVendaEmBackground usa formatter no catch genérico', () {
      final fnStart = src.indexOf('Future<(bool, String?, String?)> _salvarVendaEmBackground');
      expect(fnStart, greaterThan(-1));
      final fnEnd = src.indexOf('@override', fnStart);
      final fnSlice = src.substring(
        fnStart,
        fnEnd > fnStart ? fnEnd : fnStart + 20000,
      );
      expect(fnSlice.contains('formatSalvarVendaErrorForUser(e)'), isTrue);
    });

    test('erro crítico tem branch dedicado no formatter', () {
      final helper = File('lib/core/dart_error_unwrap.dart').readAsStringSync();
      expect(helper.contains('VendaPersistenciaInconsistenciaCritica'), isTrue);
      expect(helper.contains('_mensagemInconsistenciaCriticaVenda'), isTrue);
    });

    test('pagamento incompleto bloqueia antes de _salvarVendaEmBackground', () {
      final execStart = src.indexOf('Future<void> _executarFinalizacaoVenda()');
      final saveCall = src.indexOf('_salvarVendaEmBackground(');
      final guard = src.indexOf('novaVendaPagamentoImpedeSalvar');
      expect(execStart, greaterThan(-1));
      expect(guard, greaterThan(execStart));
      expect(guard, lessThan(saveCall));
      expect(src.contains('kNovaVendaPagamentoIncompletoMensagem'), isTrue);
    });

    test('correção de UX é global e não hardcodeia loja/produto', () {
      for (final path in [
        'lib/core/dart_error_unwrap.dart',
        'lib/core/nova_venda_payment_guard.dart',
        'lib/screens/nova_venda_modal.dart',
      ]) {
        final text = File(path).readAsStringSync().toLowerCase();
        expect(text.contains('mirjoias'), isFalse, reason: path);
        expect(text.contains('brinco-cora'), isFalse, reason: path);
      }
    });

    test('gate de variação/grade permanece fail-closed no backend', () {
      final commands =
          File('functions/src/stockCatalogCommands.js').readAsStringSync();
      expect(commands.contains('authorizeVariationSaleItems'), isTrue);
      expect(commands.contains('GRADE_SALE_NOT_AUTHORIZED'), isTrue);
      expect(commands.contains('VARIATION_SALE_PRODUCT_NOT_AUTHORIZED'), isTrue);
      expect(
        commands.contains("if (command.kind === 'sale') await authorizeVariationSaleItems"),
        isTrue,
      );
    });
  });
}
