import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/models/produto.dart';

Produto _produto({int qty = 0, int rev = 0}) => Produto(
      nome: 'Anel',
      custoReal: 0,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 85,
      quantidade: qty,
      precoUnitario: 85,
      categoria: 'Aneis',
      dataEntrada: DateTime(2026, 1, 1),
      stockRevision: rev,
    );

void main() {
  group('estoqueQuantidadeUiLabel', () {
    test('confirmado sem pendência mostra Qtd', () {
      final p = _produto(qty: 1);
      expect(estoqueQuantidadeUiLabel(p), 'Qtd: 1');
    });

    test('pendência sem remoto mostra alteração pendente', () {
      final p = _produto(qty: 1, rev: 1);
      markPendingStockMutation(p, operationId: 'op-1', baseRevision: 1);
      expect(estoqueQuantidadeUiLabel(p), 'Alteração pendente · qtd 1');
      expect(estoqueQuantidadeUiLabel(p, confirmedRemoteQty: 0),
          'Confirmado: 0 · Pretendida: 1');
    });

    test('pendência com qtd 0 não significa zero operações', () {
      final p = _produto(qty: 0, rev: 1);
      markPendingStockMutation(p, operationId: 'op-zero', baseRevision: 1);
      expect(hasPendingStockMutation(p), isTrue);
      expect(estoqueQuantidadeUiLabel(p), 'Alteração pendente · qtd 0');
      expect(estoqueQuantidadeUiLabel(p).contains('pendente: 0'), isFalse);
    });
  });

  group('sellableConfirmedQuantity', () {
    test('sem pendência usa local', () {
      final p = _produto(qty: 2);
      expect(sellableConfirmedQuantity(local: p, remoteQty: 0), 2);
    });

    test('com pendência usa remoto confirmado', () {
      final p = _produto(qty: 1, rev: 1);
      markPendingStockMutation(p, operationId: 'op-1', baseRevision: 1);
      expect(sellableConfirmedQuantity(local: p, remoteQty: 0), 0);
      expect(sellableConfirmedQuantity(local: p, remoteQty: 1), 1);
    });
  });

  group('formatSalvarVendaErrorForUser — precondition', () {
    test('failed-precondition não vira erro de conexão', () {
      final msg = formatSalvarVendaErrorForUser(
        FirebaseException(
          plugin: 'cloud_functions',
          code: 'failed-precondition',
          message: 'Stock protocol unavailable or migration incomplete',
        ),
      );
      expect(msg.toLowerCase(), isNot(contains('internet')));
      expect(msg.toLowerCase(), isNot(contains('conexão ao salvar')));
      expect(msg.toLowerCase(), contains('estoque'));
    });

    test('aborted revision conflict orienta atualizar tela', () {
      final msg = formatSalvarVendaErrorForUser(
        FirebaseException(
          plugin: 'cloud_functions',
          code: 'aborted',
          message: 'Stock revision conflict',
        ),
      );
      expect(msg.toLowerCase(), contains('atualize'));
      expect(msg.toLowerCase(), isNot(contains('internet')));
    });

    test('unavailable real continua como conexão', () {
      final msg = formatSalvarVendaErrorForUser(
        FirebaseException(
          plugin: 'cloud_functions',
          code: 'unavailable',
          message: 'UNAVAILABLE',
        ),
      );
      expect(msg.toLowerCase(), contains('conexão'));
    });
  });
}
