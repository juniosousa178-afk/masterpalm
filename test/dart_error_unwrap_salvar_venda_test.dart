import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
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
      expect(msg.toLowerCase(), contains('estoque insuficiente'));
      expect(msg, isNot(contains('converted Future')));
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
      final fnSlice = src.substring(fnStart, fnStart + 4500);
      expect(fnSlice.contains('formatSalvarVendaErrorForUser(e)'), isTrue);
    });

    test('erro crítico tem branch dedicado no formatter', () {
      final helper = File('lib/core/dart_error_unwrap.dart').readAsStringSync();
      expect(helper.contains('VendaPersistenciaInconsistenciaCritica'), isTrue);
      expect(helper.contains('_mensagemInconsistenciaCriticaVenda'), isTrue);
    });
  });
}
