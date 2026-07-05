import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
import 'package:master_palm/services/vendas_service.dart';

class _FakeConvertedFutureError implements Exception {
  _FakeConvertedFutureError(this.error);
  final Object error;

  @override
  String toString() =>
      "Error: Dart exception thrown from converted Future. "
      "Use the properties 'error' to fetch the boxed error and 'stack' to recover the stack trace.";
}

class _CountingInteropWrapper implements Exception {
  _CountingInteropWrapper({required this.onRead, required this.inner});
  final void Function() onRead;
  final Object inner;

  Object get error {
    onRead();
    return inner;
  }

  @override
  String toString() =>
      "Error: Dart exception thrown from converted Future. "
      "Use the properties 'error' to fetch the boxed error and 'stack' to recover the stack trace.";
}

void main() {
  group('unwrapDartInteropError', () {
    test('ArgumentError simples permanece identificável', () {
      final err = ArgumentError('campo inválido');
      expect(unwrapDartInteropError(err), same(err));
      expect(unwrapDartInteropError(err).toString(), contains('campo inválido'));
    });

    test('StateError simples permanece identificável', () {
      final err = StateError('estado inválido');
      expect(unwrapDartInteropError(err), same(err));
    });

    test('wrapper converted Future é desembrulhado', () {
      const inner = 'Estoque insuficiente para "Anel".';
      final wrapped = _FakeConvertedFutureError(Exception(inner));
      final root = unwrapDartInteropError(wrapped);
      expect(root.toString(), contains('Estoque insuficiente'));
      expect(root.toString(), isNot(contains('converted Future')));
    });

    test('profundidade máxima impede loop infinito', () {
      Object current = Exception('folha');
      for (var i = 0; i < 8; i++) {
        current = _FakeConvertedFutureError(current);
      }
      final root = unwrapDartInteropError(current, maxDepth: 2);
      expect(root.toString().toLowerCase(), contains('converted future'));
    });

    test('erro já normalizado não muda', () {
      final err = Exception('mensagem estável');
      expect(unwrapDartInteropError(err), same(err));
      expect(unwrapDartInteropError(err), same(unwrapDartInteropError(err)));
    });

    test('não reexecuta lógica além de ler propriedades de encadeamento', () {
      var leituras = 0;
      final inner = _CountingInteropWrapper(
        onRead: () => leituras++,
        inner: Exception('erro interno'),
      );
      unwrapDartInteropError(inner, maxDepth: 6);
      expect(leituras, lessThanOrEqualTo(6));
      expect(leituras, greaterThan(0));
    });
  });

  group('formatDartErrorForUser', () {
    test('FirebaseException não vaza code/plugin na mensagem de UX', () {
      final msg = formatDartErrorForUser(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        ),
      );
      expect(msg.toLowerCase(), contains('permiss'));
      expect(msg, isNot(contains('code=')));
      expect(msg, isNot(contains('plugin=')));
      expect(msg, isNot(contains('[core/')));
    });

    test('Instance of vira mensagem genérica segura', () {
      final msg = formatDartErrorForUser(Object());
      expect(msg, isNot(startsWith("Instance of '")));
      expect(msg, contains('Falha na operação'));
    });

    test('converted Future sem erro interno vira mensagem genérica', () {
      final msg = formatDartErrorForUser(_FakeConvertedFutureError(Object()));
      expect(msg, isNot(contains('converted Future')));
      expect(msg, contains('Falha na operação'));
    });
  });

  group('formatSalvarVendaErrorForUser', () {
    test('VendaPersistenciaInconsistenciaCritica direta é preservada', () {
      final critica = VendaPersistenciaInconsistenciaCritica(
        erroPersistencia: StateError('hive fail'),
        erroEstorno: StateError('rollback fail'),
      );
      final msg = formatSalvarVendaErrorForUser(critica);
      expect(msg.toLowerCase(), contains('não foi concluída'));
      expect(msg.toLowerCase(), contains('estoque'));
      expect(msg.toLowerCase(), contains('não repita'));
      expect(msg, isNot(contains('hive fail')));
      expect(msg, isNot(contains('rollback fail')));
      expect(msg, isNot(contains('StateError')));
    });

    test('VendaPersistenciaInconsistenciaCritica embrulhada é reconhecida', () {
      final critica = VendaPersistenciaInconsistenciaCritica(
        erroPersistencia: StateError('hive fail'),
        erroEstorno: StateError('rollback fail'),
      );
      final wrapped = _FakeConvertedFutureError(critica);
      final msg = formatSalvarVendaErrorForUser(wrapped);
      expect(msg.toLowerCase(), contains('não repita'));
      expect(msg, isNot(contains('converted Future')));
    });

    test('fallback não contém artefatos técnicos', () {
      final msg = formatSalvarVendaErrorForUser(
        _FakeConvertedFutureError(Object()),
      );
      for (final forbidden in [
        'Instance of',
        'DartError',
        '[core/',
        'converted Future',
        'code=',
        'plugin=',
      ]) {
        expect(msg.contains(forbidden), isFalse, reason: 'contém $forbidden');
      }
      expect(msg, contains('Não foi possível concluir a venda'));
    });

    test('classifica estoque insuficiente', () {
      final msg = formatSalvarVendaErrorForUser(
        Exception('Estoque insuficiente para "Pingente". Disponível: 1, solicitado: 3.'),
      );
      expect(msg.toLowerCase(), contains('estoque insuficiente'));
    });
  });
}
