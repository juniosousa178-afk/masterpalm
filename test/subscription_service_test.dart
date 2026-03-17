// test/subscription_service_test.dart
// Testes das constantes de limites por plano (trial, free_limited, paid).
// Não chama Firebase; só valida os maps estáticos para evitar regressão.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/subscription_service.dart';

void main() {
  group('SubscriptionService - trialLimits', () {
    test('tem chaves esperadas', () {
      expect(SubscriptionService.trialLimits.containsKey('maxProducts'), true);
      expect(SubscriptionService.trialLimits.containsKey('maxClients'), true);
      expect(SubscriptionService.trialLimits.containsKey('vendasMes'), true);
      expect(SubscriptionService.trialLimits.containsKey('maxImagesPerProduct'), true);
      expect(SubscriptionService.trialLimits.containsKey('maxBanners'), true);
    });
    test('valores do trial (90 dias)', () {
      expect(SubscriptionService.trialLimits['maxProducts'], 80);
      expect(SubscriptionService.trialLimits['maxClients'], 150);
      expect(SubscriptionService.trialLimits['vendasMes'], 50);
      expect(SubscriptionService.trialLimits['maxImagesPerProduct'], 3);
      expect(SubscriptionService.trialLimits['maxBanners'], 6);
    });
  });

  group('SubscriptionService - freeLimitedLimits', () {
    test('tem chaves esperadas', () {
      expect(SubscriptionService.freeLimitedLimits.containsKey('maxProducts'), true);
      expect(SubscriptionService.freeLimitedLimits.containsKey('maxClients'), true);
      expect(SubscriptionService.freeLimitedLimits.containsKey('vendasMes'), true);
      expect(SubscriptionService.freeLimitedLimits.containsKey('maxImagesPerProduct'), true);
      expect(SubscriptionService.freeLimitedLimits.containsKey('maxBanners'), true);
    });
    test('valores do free_limited (após 90 dias)', () {
      expect(SubscriptionService.freeLimitedLimits['maxProducts'], 10);
      expect(SubscriptionService.freeLimitedLimits['maxClients'], 20);
      expect(SubscriptionService.freeLimitedLimits['vendasMes'], 10);
      expect(SubscriptionService.freeLimitedLimits['maxImagesPerProduct'], 1);
      expect(SubscriptionService.freeLimitedLimits['maxBanners'], 1);
    });
  });

  group('SubscriptionService - paidLimits', () {
    test('tem chaves esperadas', () {
      expect(SubscriptionService.paidLimits.containsKey('maxProducts'), true);
      expect(SubscriptionService.paidLimits.containsKey('maxClients'), true);
      expect(SubscriptionService.paidLimits.containsKey('vendasMes'), true);
      expect(SubscriptionService.paidLimits.containsKey('maxImagesPerProduct'), true);
      expect(SubscriptionService.paidLimits.containsKey('maxBanners'), true);
    });
    test('valores do plano pago (ilimitado + 6 fotos/banners)', () {
      expect(SubscriptionService.paidLimits['maxProducts'], 999999);
      expect(SubscriptionService.paidLimits['maxClients'], 999999);
      expect(SubscriptionService.paidLimits['vendasMes'], 999999);
      expect(SubscriptionService.paidLimits['maxImagesPerProduct'], 6);
      expect(SubscriptionService.paidLimits['maxBanners'], 6);
    });
  });
}
