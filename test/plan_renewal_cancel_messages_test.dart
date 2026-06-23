import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/plan_renewal_messages.dart';

void main() {
  group('planRenewalErrorMessage', () {
    test('RECURRING_PLAN_BILLING_DISABLED não aparece cru', () {
      final msg = planRenewalErrorMessage(
        Exception('RECURRING_PLAN_BILLING_DISABLED'),
      );
      expect(msg, isNotNull);
      expect(msg!.toLowerCase(), isNot(contains('recurring_plan_billing_disabled')));
      expect(msg, contains('suporte'));
    });

    test('ASSINATURA_RECORRENTE_NAO_ENCONTRADA', () {
      final msg = planRenewalErrorMessage(
        Exception('ASSINATURA_RECORRENTE_NAO_ENCONTRADA'),
      );
      expect(msg, contains('Não encontramos uma renovação ativa'));
    });

    test('ASSINATURA_JA_CANCELADA', () {
      final msg = planRenewalErrorMessage(
        Exception('ASSINATURA_JA_CANCELADA'),
      );
      expect(msg, contains('já está cancelada'));
    });

    test('erro desconhecido retorna null', () {
      expect(planRenewalErrorMessage(Exception('outro')), isNull);
    });
  });

  group('isInternalPlanRenewalErrorCode', () {
    test('bloqueia códigos internos na propagação crua', () {
      expect(isInternalPlanRenewalErrorCode('RECURRING_PLAN_BILLING_DISABLED'), true);
      expect(isInternalPlanRenewalErrorCode('Perfil não encontrado.'), false);
    });
  });

  group('formatPlanRenewalCancelSuccess', () {
    test('mensagem de sucesso com plano e data', () {
      final msg = formatPlanRenewalCancelSuccess(
        planLabel: 'Básico',
        periodEnd: DateTime(2026, 6, 30),
      );
      expect(msg, contains('Renovação cancelada com sucesso'));
      expect(msg, contains('Seu plano Básico continua ativo até 30/06/2026'));
      expect(msg, contains('plano gratuito limitado'));
    });
  });
}
