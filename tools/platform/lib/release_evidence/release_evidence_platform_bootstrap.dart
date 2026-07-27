import '../core/provider_registry.dart';
import '../interfaces/quality_gate_provider.dart';
import '../interfaces/release_evidence_provider.dart';
import '../interfaces/release_governance_provider.dart';
import '../providers/platform_release_evidence_provider.dart';
import 'policies/release_attestation_policy_v1.dart';
import 'policies/release_evidence_policy_v1.dart';
import 'policies/release_verification_policy_v1.dart';
import 'release_evidence_policy_registry.dart';
import 'release_evidence_source_resolver.dart';
import 'stores/in_memory_release_evidence_store.dart';

/// Composition root for Release Evidence integration.
class ReleaseEvidencePlatformBootstrap {
  const ReleaseEvidencePlatformBootstrap._();

  static void register({
    required ProviderRegistry registry,
    ReleaseEvidenceProvider? releaseEvidenceProvider,
    InMemoryReleaseEvidenceStore? store,
    ReleaseEvidencePolicyRegistry? evidencePolicyRegistry,
    ReleaseAttestationPolicyRegistry? attestationPolicyRegistry,
    ReleaseVerificationPolicyRegistry? verificationPolicyRegistry,
  }) {
    if (registry.isRegistered<ReleaseEvidenceProvider>()) return;

    if (!registry.isRegistered<ReleaseGovernanceProvider>()) {
      throw StateError(
        'ReleaseGovernanceProvider must be registered before ReleaseEvidenceProvider',
      );
    }

    final evidencePolicies =
        evidencePolicyRegistry ?? ReleaseEvidencePolicyRegistry();
    if (!evidencePolicies.isFrozen) {
      evidencePolicies.register(ReleaseEvidencePolicyV1.create());
      evidencePolicies.freeze();
    }

    final attestationPolicies =
        attestationPolicyRegistry ?? ReleaseAttestationPolicyRegistry();
    if (!attestationPolicies.isFrozen) {
      attestationPolicies.register(ReleaseAttestationPolicyV1.create());
      attestationPolicies.freeze();
    }

    final verificationPolicies =
        verificationPolicyRegistry ?? ReleaseVerificationPolicyRegistry();
    if (!verificationPolicies.isFrozen) {
      verificationPolicies.register(ReleaseVerificationPolicyV1.create());
      verificationPolicies.freeze();
    }

    final sourceResolver = ReleaseEvidenceSourceResolver(
      qualityGateProvider: registry.resolve<QualityGateProvider>(),
      releaseGovernanceProvider: registry.resolve<ReleaseGovernanceProvider>(),
      evidencePolicyRegistry: evidencePolicies,
      attestationPolicyRegistry: attestationPolicies,
      verificationPolicyRegistry: verificationPolicies,
    );

    registry.registerInstance<ReleaseEvidenceProvider>(
      releaseEvidenceProvider ??
          PlatformReleaseEvidenceProvider(
            sourceResolver: sourceResolver,
            evidencePolicyRegistry: evidencePolicies,
            attestationPolicyRegistry: attestationPolicies,
            verificationPolicyRegistry: verificationPolicies,
            store: store ?? InMemoryReleaseEvidenceStore(),
          ),
    );
  }
}
