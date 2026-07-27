import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'persistent_artifact_operational_fixtures.dart';
import 'persistent_artifact_test_fixtures.dart';

class _NullReleaseEvidenceProvider implements ReleaseEvidenceProvider {
  @override
  Future<ReleaseEvidenceResult> evaluate(
          ReleaseEvidenceRequest request) async =>
      throw UnimplementedError();
  @override
  Future<ReleaseEvidenceResult> evaluateAndPublish(
    ReleaseEvidenceRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String bundleId) async {}
  @override
  Future<ReleaseEvidenceBundle?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async =>
      null;
  @override
  Future<ReleaseEvidenceBundle?> load(String bundleId) async => null;
  @override
  Future<void> publish(ReleaseEvidenceBundle bundle) async {}
  @override
  Future<List<ReleaseEvidenceBundle>> query(ReleaseEvidenceQuery query) async =>
      const [];
}

class _NullReleaseSupplyChainProvider implements ReleaseSupplyChainProvider {
  @override
  Future<ReleaseSupplyChainResult> evaluate(
    ReleaseSupplyChainRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<ReleaseSupplyChainResult> evaluateAndPublish(
    ReleaseSupplyChainRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String snapshotId) async {}
  @override
  Future<ReleaseSupplyChainSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? supplyChainPolicyId,
  }) async =>
      null;
  @override
  Future<ReleaseSupplyChainSnapshot?> load(String snapshotId) async => null;
  @override
  Future<void> publish(ReleaseSupplyChainSnapshot snapshot) async {}
  @override
  Future<List<ReleaseSupplyChainSnapshot>> query(
    ReleaseSupplyChainQuery query,
  ) async =>
      const [];
}

class _NullCicdProvider implements CicdIntegrationProvider {
  @override
  Future<CicdIntegrationResult> evaluate(
          CicdIntegrationRequest request) async =>
      throw UnimplementedError();
  @override
  Future<CicdIntegrationResult> evaluateAndPublish(
    CicdIntegrationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String snapshotId) async {}
  @override
  Future<CicdIntegrationSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? pipelineIntegrationPolicyId,
  }) async =>
      null;
  @override
  Future<CicdIntegrationSnapshot?> load(String snapshotId) async => null;
  @override
  Future<void> publish(CicdIntegrationSnapshot snapshot) async {}
  @override
  Future<List<CicdIntegrationSnapshot>> query(
          CicdIntegrationQuery query) async =>
      const [];
}

class _NullCryptographicTrustProvider implements CryptographicTrustProvider {
  @override
  Future<CryptographicDigest?> computeDigest({
    required List<int> subjectBytes,
    required CryptographicDigest descriptor,
  }) async =>
      null;
  @override
  Future<CryptographicTrustEvaluationResult> evaluate(
    CryptographicTrustEvaluationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<CryptographicTrustEvaluationResult> evaluateAndPublish(
    CryptographicTrustEvaluationRequest request,
  ) async =>
      throw UnimplementedError();
  @override
  Future<void> invalidate(String snapshotId) async {}
  @override
  Future<CryptographicTrustSnapshot?> latest({
    required String projectId,
    String? releaseId,
    String? policyId,
  }) async =>
      null;
  @override
  Future<CryptographicTrustSnapshot?> load(String snapshotId) async => null;
  @override
  Future<void> publish(CryptographicTrustSnapshot snapshot) async {}
  @override
  Future<List<CryptographicTrustSnapshot>> query(
          CryptographicTrustQuery query) async =>
      const [];
  @override
  Future<CryptographicSigningPrimitiveResult> sign({
    required CryptographicKeyReference keyReference,
    required List<int> digestBytes,
    required CryptographicSignatureEnvelope template,
  }) async =>
      throw UnimplementedError();
  @override
  Future<List<CryptographicAttestationVerificationResult>> verifyAttestation({
    required CryptographicAttestationStatement attestation,
    required List<CryptographicSignatureVerificationResult> signatureResults,
  }) async =>
      const [];
  @override
  Future<CryptographicVerificationResult?> verifySignature({
    required CryptographicSignatureEnvelope envelope,
    required List<int> subjectBytes,
    required String projectId,
    String? releaseId,
  }) async =>
      null;
}

class PersistentArtifactTestStack {
  PersistentArtifactTestStack({
    required this.provider,
    required this.store,
    required this.policyRegistry,
    required this.sourceResolver,
  });

  final PlatformPersistentArtifactProvider provider;
  final InMemoryPersistentArtifactSnapshotStore store;
  final PersistentArtifactPolicyRegistry policyRegistry;
  final PersistentArtifactSourceResolver sourceResolver;
}

PersistentArtifactTestStack createTestStack({
  InMemoryPersistentArtifactSnapshotStore? store,
  PersistentArtifactPolicyRegistry? policyRegistry,
}) {
  final resolvedStore = store ?? InMemoryPersistentArtifactSnapshotStore();
  final resolvedRegistry = policyRegistry ??
      PersistentArtifactPolicyRegistry(registerDefaults: true);
  final resolver = PersistentArtifactSourceResolver(
    releaseEvidenceProvider: _NullReleaseEvidenceProvider(),
    releaseSupplyChainProvider: _NullReleaseSupplyChainProvider(),
    cicdIntegrationProvider: _NullCicdProvider(),
    cryptographicTrustProvider: _NullCryptographicTrustProvider(),
  );
  final provider = PlatformPersistentArtifactProvider(
    policyRegistry: resolvedRegistry,
    sourceResolver: resolver,
    store: resolvedStore,
  );
  return PersistentArtifactTestStack(
    provider: provider,
    store: resolvedStore,
    policyRegistry: resolvedRegistry,
    sourceResolver: resolver,
  );
}

Future<PersistentArtifactEvaluationResult> evaluatePassingSnapshot({
  PersistentArtifactTestStack? stack,
}) async {
  final resolved = stack ?? createTestStack();
  return resolved.provider.evaluate(
    fixtureEvaluationRequest(metadata: const {'scenario': 'passing'}),
  );
}

Future<PersistentArtifactEvaluationResult> publishPassingSnapshot({
  PersistentArtifactTestStack? stack,
}) async {
  final resolved = stack ?? createTestStack();
  return resolved.provider.evaluateAndPublish(
    fixtureEvaluationRequest(metadata: const {'scenario': 'published'}),
  );
}

Future<PersistentArtifactEvaluationResult> evaluatePartialScenario({
  PersistentArtifactTestStack? stack,
}) async {
  final resolved = stack ?? createTestStack();
  return resolved.provider.evaluate(
    fixtureEvaluationRequest(
      metadata: const {'scenario': 'partial', 'expectSources': 'unavailable'},
    ),
  );
}

Future<PersistentArtifactOperationResult> evaluateBlockedDeletionScenario({
  PersistentArtifactTestStack? stack,
}) async {
  final resolved = stack ?? createTestStack();
  return resolved.provider.evaluateDeletion(
    fixtureEvaluationRequest(metadata: const {'legalHold': 'true'}),
    force: true,
  );
}

Future<PersistentArtifactOperationResult> evaluateDeletionEligibleScenario({
  PersistentArtifactTestStack? stack,
}) async {
  final resolved = stack ?? createTestStack();
  return resolved.provider.evaluateDeletion(
    fixtureEvaluationRequest(metadata: const {'legalHold': 'false'}),
    force: true,
  );
}

Future<PersistentArtifactOperationResult> evaluateLifecycleScenario({
  PersistentArtifactTestStack? stack,
}) async {
  final resolved = stack ?? createTestStack();
  return resolved.provider.evaluateLifecycle(fixtureEvaluationRequest());
}

Future<PersistentArtifactOperationResult> evaluatePublicationScenario({
  PersistentArtifactTestStack? stack,
}) async {
  final resolved = stack ?? createTestStack();
  return resolved.provider.evaluatePublication(fixtureEvaluationRequest());
}

Future<PersistentArtifactOperationResult> evaluateIntegrityScenario({
  PersistentArtifactTestStack? stack,
}) async {
  final resolved = stack ?? createTestStack();
  return resolved.provider.evaluateIntegrity(fixtureEvaluationRequest());
}

Future<PersistentArtifactOperationResult> evaluateRetentionScenario({
  PersistentArtifactTestStack? stack,
}) async {
  final resolved = stack ?? createTestStack();
  return resolved.provider.evaluateRetention(fixtureEvaluationRequest());
}

Future<PersistentArtifactOperationResult> evaluateReplicationScenario({
  PersistentArtifactTestStack? stack,
}) async {
  final resolved = stack ?? createTestStack();
  return resolved.provider.evaluateReplication(fixtureEvaluationRequest());
}

Future<PersistentArtifactOperationResult> evaluateAvailabilityScenario({
  PersistentArtifactTestStack? stack,
}) async {
  final resolved = stack ?? createTestStack();
  return resolved.provider.evaluateAvailability(fixtureEvaluationRequest());
}

Future<PersistentArtifactSnapshotConflictException> publishConflictingScenario({
  PersistentArtifactTestStack? stack,
}) async {
  final resolved = stack ?? createTestStack();
  final baseSnapshot = PersistentArtifactTestFixtures.validSnapshot();
  await resolved.provider.publish(baseSnapshot);
  final mutated = baseSnapshot.copyWith(
    status: PersistentArtifactInfrastructureStatus.invalidated,
  );
  try {
    await resolved.provider.publish(mutated);
    throw StateError('expected PersistentArtifactSnapshotConflictException');
  } on PersistentArtifactSnapshotConflictException catch (e) {
    return e;
  }
}

PersistentArtifactEvaluationRequest passingScenarioRequest({
  String evaluationId = 'eval-passing',
}) {
  return fixtureEvaluationRequest(
    evaluationId: evaluationId,
    metadata: const {'scenario': 'passing'},
  );
}

PersistentArtifactEvaluationRequest partialScenarioRequest({
  String evaluationId = 'eval-partial',
}) {
  return fixtureEvaluationRequest(
    evaluationId: evaluationId,
    metadata: const {'scenario': 'partial'},
  );
}

PersistentArtifactInfrastructureSnapshot conflictingScenarioSnapshot({
  PersistentArtifactInfrastructureSnapshot? base,
}) {
  final snapshot = base ?? PersistentArtifactTestFixtures.validSnapshot();
  return snapshot.copyWith(
    status: PersistentArtifactInfrastructureStatus.invalidated,
  );
}

Map<String, dynamic> loadGoldenJson(String name) {
  final file = File('test/goldens/persistent_artifacts/$name.json');
  expect(
    file.existsSync(),
    isTrue,
    reason:
        'Golden ausente: ${file.path}. Atualize manualmente conforme README.',
  );
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void saveGoldenJson(String name, Map<String, dynamic> jsonMap) {
  final file = File('test/goldens/persistent_artifacts/$name.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(jsonMap));
}

void assertPersistentArtifactGolden(
  String name,
  Map<String, dynamic> normative,
  List<String> keys,
) {
  final golden = loadGoldenJson(name);
  for (final key in keys) {
    expect(normative[key], golden[key], reason: 'golden key: $key');
  }
}
