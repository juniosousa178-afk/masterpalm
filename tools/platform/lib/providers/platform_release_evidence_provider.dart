import '../interfaces/release_evidence_provider.dart';
import '../models/release_evidence/release_attestation_policy.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_messages.dart';
import '../models/release_evidence/release_evidence_policy.dart';
import '../models/release_evidence/release_evidence_query.dart';
import '../models/release_evidence/release_evidence_request.dart';
import '../models/release_evidence/release_evidence_result.dart';
import '../models/release_evidence/release_verification_policy.dart';
import '../release_evidence/policies/release_attestation_policy_v1.dart';
import '../release_evidence/policies/release_evidence_policy_v1.dart';
import '../release_evidence/policies/release_verification_policy_v1.dart';
import '../release_evidence/release_evidence_attestation_engine.dart';
import '../release_evidence/release_evidence_bundle_builder.dart';
import '../release_evidence/release_evidence_bundle_validator.dart';
import '../release_evidence/release_evidence_collector.dart';
import '../release_evidence/release_evidence_exceptions.dart';
import '../release_evidence/release_evidence_policy_registry.dart';
import '../release_evidence/release_evidence_source_resolver.dart';
import '../release_evidence/release_evidence_verification_engine.dart';
import '../release_evidence/resolved_release_evidence_sources.dart';
import '../release_evidence/stores/release_evidence_store.dart';

/// Platform implementation of [ReleaseEvidenceProvider].
class PlatformReleaseEvidenceProvider implements ReleaseEvidenceProvider {
  PlatformReleaseEvidenceProvider({
    required ReleaseEvidenceSourceResolver sourceResolver,
    required ReleaseEvidencePolicyRegistry evidencePolicyRegistry,
    required ReleaseAttestationPolicyRegistry attestationPolicyRegistry,
    required ReleaseVerificationPolicyRegistry verificationPolicyRegistry,
    required ReleaseEvidenceStore store,
    ReleaseEvidenceCollector? collector,
    ReleaseEvidenceBundleBuilder? bundleBuilder,
    ReleaseEvidenceAttestationEngine? attestationEngine,
    ReleaseEvidenceVerificationEngine? verificationEngine,
    ReleaseEvidenceBundleValidator? bundleValidator,
  })  : _sourceResolver = sourceResolver,
        _evidencePolicyRegistry = evidencePolicyRegistry,
        _attestationPolicyRegistry = attestationPolicyRegistry,
        _verificationPolicyRegistry = verificationPolicyRegistry,
        _store = store,
        _collector = collector ?? const ReleaseEvidenceCollector(),
        _bundleBuilder = bundleBuilder ?? ReleaseEvidenceBundleBuilder(),
        _attestationEngine =
            attestationEngine ?? ReleaseEvidenceAttestationEngine(),
        _verificationEngine =
            verificationEngine ?? ReleaseEvidenceVerificationEngine(),
        _bundleValidator =
            bundleValidator ?? const ReleaseEvidenceBundleValidator();

  final ReleaseEvidenceSourceResolver _sourceResolver;
  final ReleaseEvidencePolicyRegistry _evidencePolicyRegistry;
  final ReleaseAttestationPolicyRegistry _attestationPolicyRegistry;
  final ReleaseVerificationPolicyRegistry _verificationPolicyRegistry;
  final ReleaseEvidenceStore _store;
  final ReleaseEvidenceCollector _collector;
  final ReleaseEvidenceBundleBuilder _bundleBuilder;
  final ReleaseEvidenceAttestationEngine _attestationEngine;
  final ReleaseEvidenceVerificationEngine _verificationEngine;
  final ReleaseEvidenceBundleValidator _bundleValidator;

  @override
  Future<ReleaseEvidenceResult> evaluate(
    ReleaseEvidenceRequest request,
  ) async {
    final evidencePolicy = _resolveEvidencePolicy(request);
    if (evidencePolicy == null) {
      throw ReleaseEvidencePolicyNotFoundException(
        request.evidencePolicyId ?? ReleaseEvidencePolicyV1.policyId,
        policyVersion: request.evidencePolicyVersion,
      );
    }

    final attestationPolicy = _resolveAttestationPolicy(request);
    final verificationPolicy = _resolveVerificationPolicy(request);

    final sources = await _sourceResolver.resolveAll(
      request,
      injectedEvidencePolicy: evidencePolicy,
      injectedAttestationPolicy: attestationPolicy,
      injectedVerificationPolicy: verificationPolicy,
    );

    return _evaluatePipeline(
      request: request,
      sources: sources,
      evidencePolicy: evidencePolicy,
      verificationPolicy: verificationPolicy,
    );
  }

  @override
  Future<ReleaseEvidenceResult> evaluateAndPublish(
    ReleaseEvidenceRequest request,
  ) async {
    final result = await evaluate(request);
    final bundle = result.bundle;
    if (bundle == null) return result;

    final validation = _bundleValidator.validate(bundle);
    if (!validation.isValid) {
      return ReleaseEvidenceResult(
        status: ReleaseEvidenceResultStatus.failure,
        bundle: bundle,
        verificationResult: result.verificationResult,
        policyReference: result.policyReference,
        warnings: result.warnings,
        errors: result.errors,
        limitations: result.limitations,
        sourceResolutionSummary: result.sourceResolutionSummary,
      );
    }

    final existing = await _store.load(bundle.metadata.bundleId);
    if (existing != null) {
      return ReleaseEvidenceResult(
        status: result.status,
        bundle: existing,
        verificationResult: result.verificationResult,
        policyReference: result.policyReference,
        warnings: result.warnings,
        errors: result.errors,
        limitations: result.limitations,
        sourceResolutionSummary: result.sourceResolutionSummary,
        publicationStatus: ReleaseEvidencePublicationStatus.skipped.wireName,
      );
    }

    await _store.save(bundle);
    final saved = await _store.load(bundle.metadata.bundleId);
    return ReleaseEvidenceResult(
      status: result.status,
      bundle: saved ?? bundle,
      verificationResult: result.verificationResult,
      policyReference: result.policyReference,
      warnings: result.warnings,
      errors: result.errors,
      limitations: result.limitations,
      sourceResolutionSummary: result.sourceResolutionSummary,
      publicationStatus: ReleaseEvidencePublicationStatus.published.wireName,
    );
  }

  @override
  Future<void> publish(ReleaseEvidenceBundle bundle) async {
    await _store.save(bundle);
  }

  @override
  Future<ReleaseEvidenceBundle?> load(String bundleId) {
    return _store.load(bundleId);
  }

  @override
  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) {
    return _store.latest(
      projectId: projectId,
      releaseId: releaseId,
      policyId: policyId,
    );
  }

  @override
  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query) {
    return _store.query(query);
  }

  @override
  Future<void> invalidate(String bundleId) async {
    if (!await _store.exists(bundleId)) {
      throw ReleaseEvidenceNotFoundException(bundleId);
    }
    await _store.invalidate(bundleId);
  }

  Future<ReleaseEvidenceResult> _evaluatePipeline({
    required ReleaseEvidenceRequest request,
    required ResolvedReleaseEvidenceSources sources,
    required ReleaseEvidencePolicy evidencePolicy,
    ReleaseVerificationPolicy? verificationPolicy,
  }) async {
    final context = ReleaseEvidenceEvaluationContext(
      request: request,
      sources: sources,
      evidencePolicy: evidencePolicy,
      attestationPolicy: sources.attestationPolicy.resolvedArtifact,
      verificationPolicy: verificationPolicy,
    );

    final collected = _collector.collect(context);
    final bundle = _bundleBuilder.build(
      context: context,
      collected: collected,
      evaluatedAt: request.referenceTime,
    );

    final attestationPolicy = context.attestationPolicy;
    final attestationWarnings = <ReleaseEvidenceWarning>[];
    final attestationLimitations = <ReleaseEvidenceLimitation>[];
    if (attestationPolicy != null) {
      for (final attestation in bundle.attestations) {
        final evaluation = _attestationEngine.evaluate(
          attestation: attestation,
          policy: attestationPolicy,
          bundle: bundle,
          referenceTime: request.referenceTime,
          expectedProjectId: request.releaseContext.projectId,
          expectedReleaseId: request.releaseContext.releaseId,
          expectedCommitId: request.releaseContext.commitId,
        );
        attestationWarnings.addAll(evaluation.warnings);
        attestationLimitations.addAll(evaluation.limitations);
      }
    }

    final verificationResult = verificationPolicy != null
        ? _verificationEngine.verify(
            bundle: bundle,
            policy: verificationPolicy,
            evaluatedAt: request.referenceTime,
            referenceTime: request.referenceTime,
          )
        : null;

    final policyReference = ReleaseEvidencePolicyReference(
      policyId: evidencePolicy.metadata.policyId,
      policyVersion: evidencePolicy.metadata.policyVersion,
      policyFingerprint: evidencePolicy.metadata.fingerprint ??
          evidencePolicy.metadata.policyId,
    );

    final warnings = <ReleaseEvidenceWarning>[
      ...sources.warnings,
      ...attestationWarnings,
    ];
    final errors = <ReleaseEvidenceError>[...sources.errors];
    final limitations = <ReleaseEvidenceLimitation>[
      ...sources.limitations,
      ...attestationLimitations,
    ];

    var status = ReleaseEvidenceResultStatus.success;
    if (errors.isNotEmpty) {
      status = ReleaseEvidenceResultStatus.failure;
    } else if (limitations.isNotEmpty || warnings.isNotEmpty) {
      status = ReleaseEvidenceResultStatus.partial;
    }
    if (bundle.eligibility.status ==
        ReleaseEvidenceEligibilityStatus.ineligible) {
      status = ReleaseEvidenceResultStatus.unavailable;
    }

    return ReleaseEvidenceResult(
      status: status,
      bundle: bundle,
      verificationResult: verificationResult,
      policyReference: policyReference,
      sourceResolutionSummary: sources.resolutionSummary,
      warnings: warnings,
      errors: errors,
      limitations: limitations,
    );
  }

  ReleaseEvidencePolicy? _resolveEvidencePolicy(
      ReleaseEvidenceRequest request) {
    final policyId =
        request.evidencePolicyId ?? ReleaseEvidencePolicyV1.policyId;
    return _evidencePolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.evidencePolicyVersion,
      allowCandidate: true,
      historicalEvaluation: request.historicalEvaluation,
    );
  }

  ReleaseAttestationPolicy? _resolveAttestationPolicy(
    ReleaseEvidenceRequest request,
  ) {
    final policyId =
        request.attestationPolicyId ?? ReleaseAttestationPolicyV1.policyId;
    return _attestationPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.attestationPolicyVersion,
      allowCandidate: true,
      historicalEvaluation: request.historicalEvaluation,
    );
  }

  ReleaseVerificationPolicy? _resolveVerificationPolicy(
    ReleaseEvidenceRequest request,
  ) {
    if (!request.includeVerification) return null;
    final policyId =
        request.verificationPolicyId ?? ReleaseVerificationPolicyV1.policyId;
    return _verificationPolicyRegistry.resolve(
      policyId: policyId,
      policyVersion: request.verificationPolicyVersion,
      allowCandidate: true,
      historicalEvaluation: request.historicalEvaluation,
    );
  }
}
