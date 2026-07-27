import '../core/provider_registry.dart';

import '../interfaces/cicd_integration_provider.dart';

import '../interfaces/cryptographic_trust_provider.dart';

import '../interfaces/release_evidence_provider.dart';

import '../interfaces/release_supply_chain_provider.dart';

import '../models/cryptographic_trust/cryptographic_trust_enums.dart';

import '../models/cryptographic_trust/cryptographic_trust_operational_enums.dart';

import '../providers/platform_cryptographic_trust_provider.dart';

import 'adapters/ed25519_signature_verifier.dart';

import 'adapters/ed25519_signer.dart';

import 'adapters/in_memory_public_key_resolver.dart';

import 'adapters/sha256_digest_provider.dart';

import 'cryptographic_algorithm_registry.dart';

import 'cryptographic_attestation_verification_service.dart';

import 'cryptographic_digest_service.dart';

import 'cryptographic_revocation_evaluator.dart';

import 'cryptographic_signature_verification_service.dart';

import 'cryptographic_signing_service.dart';

import 'cryptographic_transparency_evaluator.dart';

import 'cryptographic_trust_chain_builder.dart';

import 'cryptographic_trust_collector.dart';

import 'cryptographic_trust_engine.dart';

import 'cryptographic_trust_policy_evaluators.dart';

import 'cryptographic_trust_policy_registry.dart';

import 'cryptographic_trust_snapshot_builder.dart';

import 'cryptographic_trust_snapshot_validator.dart';

import 'cryptographic_trust_source_resolver.dart';

import 'interfaces/cryptographic_signing_key_provider.dart';

import 'stores/in_memory_cryptographic_trust_store.dart';

/// Composition root for Cryptographic Trust platform integration.

///

/// Signing is optional — verification works without a [CryptographicSigningKeyProvider].

class CryptographicTrustPlatformBootstrap {
  const CryptographicTrustPlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    CryptographicTrustProvider? cryptographicTrustProvider,
    InMemoryCryptographicTrustStore? store,
    CryptographicTrustPolicyRegistry? policyRegistry,
    CryptographicAlgorithmRegistry? algorithmRegistry,
    InMemoryPublicKeyResolver? publicKeyResolver,
    CryptographicSigningKeyProvider? signingKeyProvider,
  }) {
    if (registry.isRegistered<CryptographicTrustProvider>()) return;

    if (!registry.isRegistered<ReleaseEvidenceProvider>()) {
      throw StateError(
        'ReleaseEvidenceProvider must be registered before CryptographicTrustProvider',
      );
    }

    if (!registry.isRegistered<ReleaseSupplyChainProvider>()) {
      throw StateError(
        'ReleaseSupplyChainProvider must be registered before CryptographicTrustProvider',
      );
    }

    if (!registry.isRegistered<CicdIntegrationProvider>()) {
      throw StateError(
        'CicdIntegrationProvider must be registered before CryptographicTrustProvider',
      );
    }

    final policies = policyRegistry ?? CryptographicTrustPolicyRegistry();

    if (!policies.isFrozen) {
      policies.registerDefaultPolicies();

      policies.freeze();
    }

    final algorithms = algorithmRegistry ?? CryptographicAlgorithmRegistry();

    _registerDefaultAlgorithms(algorithms);

    final keyResolver = publicKeyResolver ?? InMemoryPublicKeyResolver();

    final sourceResolver = CryptographicTrustSourceResolver(
      releaseEvidenceProvider: registry.resolve<ReleaseEvidenceProvider>(),
      releaseSupplyChainProvider:
          registry.resolve<ReleaseSupplyChainProvider>(),
      cicdIntegrationProvider: registry.resolve<CicdIntegrationProvider>(),
      trustPolicyRegistry: policies,
    );

    final revocationEvaluator = const CryptographicRevocationEvaluator();

    final signatureVerificationService =
        CryptographicSignatureVerificationService(
      algorithmRegistry: algorithms,
      publicKeyResolver: keyResolver,
      revocationEvaluator: revocationEvaluator,
    );

    final attestationVerificationService =
        CryptographicAttestationVerificationService(
      signatureVerificationService: signatureVerificationService,
    );

    registry.registerInstance<CryptographicTrustProvider>(
      cryptographicTrustProvider ??
          PlatformCryptographicTrustProvider(
            policyRegistry: policies,
            algorithmRegistry: algorithms,
            publicKeyResolver: keyResolver,
            sourceResolver: sourceResolver,
            store: store ?? InMemoryCryptographicTrustStore(),
            signingKeyProvider: signingKeyProvider,
            collector: const CryptographicTrustCollector(),
            digestService: CryptographicDigestService(
              algorithmRegistry: algorithms,
            ),
            signingService: CryptographicSigningService(
              algorithmRegistry: algorithms,
              signingKeyProvider: signingKeyProvider,
            ),
            signatureVerificationService: signatureVerificationService,
            attestationVerificationService: attestationVerificationService,
            revocationEvaluator: revocationEvaluator,
            transparencyEvaluator: CryptographicTransparencyEvaluator(),
            trustChainBuilder: const CryptographicTrustChainBuilder(),
            engine: const CryptographicTrustEngine(),
            policyEvaluationService:
                CryptographicTrustPolicyEvaluationService(),
            snapshotBuilder: CryptographicTrustSnapshotBuilder(),
            snapshotValidator: const CryptographicTrustSnapshotValidator(),
          ),
    );
  }

  static void _registerDefaultAlgorithms(
      CryptographicAlgorithmRegistry registry) {
    if (registry.isFrozen) return;

    const sha256 = Sha256DigestProvider();

    final ed25519Verifier = Ed25519SignatureVerifier();

    final ed25519Signer = Ed25519Signer();

    registry.register(
      CryptographicAlgorithmRegistration(
        algorithmId: Sha256DigestProvider.defaultAlgorithmId,
        operation: CryptographicPrimitiveOperation.computeDigest,
        capabilities: sha256.capabilities,
        digestProvider: sha256,
      ),
    );

    registry.register(
      CryptographicAlgorithmRegistration(
        algorithmId: Ed25519SignatureVerifier.defaultAlgorithmId,
        operation: CryptographicPrimitiveOperation.verifySignature,
        capabilities: ed25519Verifier.capabilities,
        keyType: CryptographicKeyType.ed25519,
        format: CryptographicSignatureFormat.raw,
        signatureVerifier: ed25519Verifier,
      ),
    );

    registry.register(
      CryptographicAlgorithmRegistration(
        algorithmId: Ed25519Signer.defaultAlgorithmId,
        operation: CryptographicPrimitiveOperation.sign,
        capabilities: ed25519Signer.capabilities,
        keyType: CryptographicKeyType.ed25519,
        format: CryptographicSignatureFormat.raw,
        signer: ed25519Signer,
      ),
    );

    registry.freeze();
  }
}
