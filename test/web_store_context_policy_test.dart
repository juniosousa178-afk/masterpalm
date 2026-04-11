// Regressão: política Web de contexto de loja (gate unificado).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/web_store_context_policy.dart';

void main() {
  group('WebStoreContextPolicyResult', () {
    test('resolve ok + sessão igual → permitido', () {
      final r = WebStoreContextPolicyResult.evaluate(
        resolveThrew: false,
        resolvedStoreId: 'minha-loja-real',
        sessionStoreId: 'minha-loja-real',
      );
      expect(r.allowed, isTrue);
    });

    test('resolve ok + mismatch com sessão → rejeita', () {
      final r = WebStoreContextPolicyResult.evaluate(
        resolveThrew: false,
        resolvedStoreId: 'loja-a',
        sessionStoreId: 'loja-b',
      );
      expect(r.allowed, isFalse);
      expect(r.rejectionMotivo, 'resolve_session_mismatch');
    });

    test('sem resolve nem sessão segura → rejeita', () {
      final r = WebStoreContextPolicyResult.evaluate(
        resolveThrew: false,
        resolvedStoreId: null,
        sessionStoreId: '',
      );
      expect(r.allowed, isFalse);
      expect(r.rejectionMotivo, 'no_safe_store');
    });

    test('placeholder masterpalm nunca é loja válida', () {
      final r = WebStoreContextPolicyResult.evaluate(
        resolveThrew: false,
        resolvedStoreId: 'masterpalm',
        sessionStoreId: 'masterpalm',
      );
      expect(r.allowed, isFalse);
      expect(r.rejectionMotivo, 'no_safe_store');
    });

    test('exceção no resolver: só sessão válida salva', () {
      final ok = WebStoreContextPolicyResult.evaluate(
        resolveThrew: true,
        resolvedStoreId: null,
        sessionStoreId: 'loja_ok_slug',
      );
      expect(ok.allowed, isTrue);

      final bad = WebStoreContextPolicyResult.evaluate(
        resolveThrew: true,
        resolvedStoreId: null,
        sessionStoreId: '',
      );
      expect(bad.allowed, isFalse);
      expect(bad.rejectionMotivo, 'resolve_exception_sem_sessao_segura');
    });

    test('programador/root gate: mesma regra (resolve OU sessão, sem mismatch)', () {
      final r = WebStoreContextPolicyResult.evaluate(
        resolveThrew: false,
        resolvedStoreId: 'x',
        sessionStoreId: '',
      );
      expect(r.allowed, isTrue);
    });
  });
}
