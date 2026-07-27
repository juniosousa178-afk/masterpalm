import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/core/provider_registry.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/cicd_integration_provider.dart';
import 'package:masterpalm_platform/interfaces/cryptographic_trust_provider.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_supply_chain_provider.dart';
import 'package:masterpalm_platform/providers/platform_cryptographic_trust_provider.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';

void main() {
  group('CryptographicTrustPlatformBootstrap', () {
    test('registers provider after upstream dependencies', () {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      expect(core.cryptographicTrust(), isA<CryptographicTrustProvider>());
      expect(
          core.cryptographicTrust(), isA<PlatformCryptographicTrustProvider>());
    });

    test('throws when ReleaseEvidenceProvider missing', () {
      final registry = ProviderRegistry();
      expect(
        () => CryptographicTrustPlatformBootstrap.register(registry: registry),
        throwsStateError,
      );
    });

    test('throws when ReleaseSupplyChainProvider missing', () {
      final registry = ProviderRegistry();
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      registry
          .registerInstance<ReleaseEvidenceProvider>(core.releaseEvidence());
      expect(
        () => CryptographicTrustPlatformBootstrap.register(registry: registry),
        throwsStateError,
      );
    });

    test('throws when CicdIntegrationProvider missing', () {
      final registry = ProviderRegistry();
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      registry
          .registerInstance<ReleaseEvidenceProvider>(core.releaseEvidence());
      registry.registerInstance<ReleaseSupplyChainProvider>(
        core.releaseSupplyChain(),
      );
      expect(
        () => CryptographicTrustPlatformBootstrap.register(registry: registry),
        throwsStateError,
      );
    });

    test('register is idempotent', () {
      final registry = ProviderRegistry();
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      registry
          .registerInstance<ReleaseEvidenceProvider>(core.releaseEvidence());
      registry.registerInstance<ReleaseSupplyChainProvider>(
        core.releaseSupplyChain(),
      );
      registry
          .registerInstance<CicdIntegrationProvider>(core.cicdIntegration());
      CryptographicTrustPlatformBootstrap.register(registry: registry);
      CryptographicTrustPlatformBootstrap.register(registry: registry);
      expect(registry.isRegistered<CryptographicTrustProvider>(), isTrue);
    });

    test('platform bootstrap evaluate works without signing keys', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final result = await core.cryptographicTrustEvaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.evaluationId, isNotEmpty);
    });

    test('test harness mirrors bootstrap wiring for isolated tests', () {
      final registry = ProviderRegistry();
      CryptographicTrustOperationalFixtures.registerInRegistry(registry);
      expect(registry.resolve<CryptographicTrustProvider>(),
          isA<PlatformCryptographicTrustProvider>());
    });
  });
}
