// Trava síncrona contra dupla submissão na finalização de venda.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/venda_finalizacao_reentrada_guard.dart';

void main() {
  group('VendaFinalizacaoReentradaGuard', () {
    test('primeiro acionamento adquire trava; segundo é ignorado', () {
      final guard = VendaFinalizacaoReentradaGuard();
      expect(guard.tentarIniciar(), isTrue);
      expect(guard.emAndamento, isTrue);
      expect(guard.tentarIniciar(), isFalse);
    });

    test('após liberar, nova tentativa é permitida', () {
      final guard = VendaFinalizacaoReentradaGuard();
      expect(guard.tentarIniciar(), isTrue);
      guard.liberar();
      expect(guard.emAndamento, isFalse);
      expect(guard.tentarIniciar(), isTrue);
    });

    test('dois acionamentos concorrentes síncronos: apenas um inicia', () {
      final guard = VendaFinalizacaoReentradaGuard();
      var iniciou = 0;
      for (var i = 0; i < 2; i++) {
        if (guard.tentarIniciar()) iniciou++;
      }
      expect(iniciou, 1);
    });

    test('liberação após erro simulado permite nova tentativa', () {
      final guard = VendaFinalizacaoReentradaGuard();
      expect(guard.tentarIniciar(), isTrue);
      guard.liberar();
      expect(guard.tentarIniciar(), isTrue);
    });

    test('liberar é idempotente', () {
      final guard = VendaFinalizacaoReentradaGuard();
      expect(guard.tentarIniciar(), isTrue);
      guard.liberar();
      guard.liberar();
      expect(guard.emAndamento, isFalse);
      expect(guard.tentarIniciar(), isTrue);
      guard.liberar();
    });

    test('early return libera guard via finally', () async {
      final guard = VendaFinalizacaoReentradaGuard();
      await () async {
        if (!guard.tentarIniciar()) return;
        try {
          return;
        } finally {
          guard.liberar();
        }
      }();
      expect(guard.emAndamento, isFalse);
      expect(guard.tentarIniciar(), isTrue);
      guard.liberar();
    });

    test('duplo acionamento async executa corpo apenas uma vez', () async {
      final guard = VendaFinalizacaoReentradaGuard();
      var execucoes = 0;
      Future<void> fluxo() async {
        if (!guard.tentarIniciar()) return;
        try {
          execucoes++;
          await Future<void>.delayed(Duration.zero);
        } finally {
          guard.liberar();
        }
      }
      await Future.wait([fluxo(), fluxo()]);
      expect(execucoes, 1);
    });

    test('guard não permanece travado após finally simulado', () async {
      final guard = VendaFinalizacaoReentradaGuard();
      await () async {
        if (!guard.tentarIniciar()) return;
        try {
          await Future<void>.delayed(Duration.zero);
          throw StateError('erro simulado');
        } finally {
          guard.liberar();
        }
      }().catchError((_) {});
      expect(guard.emAndamento, isFalse);
      expect(guard.tentarIniciar(), isTrue);
      guard.liberar();
    });
  });

  group('nova_venda_modal — trava de reentrada no código', () {
    late String src;

    setUp(() {
      src = File('lib/screens/nova_venda_modal.dart').readAsStringSync();
    });

    test('usa VendaFinalizacaoReentradaGuard', () {
      expect(src.contains('VendaFinalizacaoReentradaGuard'), isTrue);
      expect(src.contains('tentarIniciar()'), isTrue);
    });

    test('trava síncrona antes do dialog em _finalizarVenda', () {
      final fnStart = src.indexOf('Future<void> _finalizarVenda()');
      final fnEnd = src.indexOf('Future<void> _executarFinalizacaoVenda()');
      expect(fnStart, greaterThan(-1));
      final body = src.substring(fnStart, fnEnd);
      final iGuard = body.indexOf('tentarIniciar()');
      final iDialog = body.indexOf('FinalizarVendaConfirmacaoDialog.show');
      expect(iGuard, greaterThan(-1));
      expect(iDialog, greaterThan(iGuard));
    });

    test('botão Finalizar fica indisponível durante processamento', () {
      expect(src.contains('_finalizacaoReentradaGuard.emAndamento'), isTrue);
    });

    test('finally libera trava em _finalizarVenda', () {
      final fnStart = src.indexOf('Future<void> _finalizarVenda()');
      final fnEnd = src.indexOf('Future<void> _executarFinalizacaoVenda()');
      final body = src.substring(fnStart, fnEnd);
      expect(body.contains('} finally {'), isTrue);
      expect(body.contains('_finalizacaoReentradaGuard.liberar()'), isTrue);
    });
  });
}
