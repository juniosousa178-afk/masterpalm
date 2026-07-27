import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';

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
    CryptographicTrustQuery query,
  ) async =>
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

class FilesystemIntegrationStack {
  FilesystemIntegrationStack({
    required this.root,
    required this.config,
    required this.registry,
    required this.provider,
  });

  final Directory root;
  final SecureFilesystemBackendConfig config;
  final PersistentArtifactBackendRegistry registry;
  final PlatformPersistentArtifactProvider provider;
}

FilesystemIntegrationStack createFilesystemStack({
  bool productionContext = false,
  bool enableRecoveryInspector = true,
}) {
  final root = Directory.systemTemp.createTempSync('mp-pa-fs-int-');
  final config = SecureFilesystemBackendConfig(
    backendId: 'fs-int',
    rootDirectory: root.path,
    namespacePrefix: 'test-ns',
    maximumContentSizeBytes: 1024 * 1024,
    quarantineEnabled: true,
    enableRecoveryInspector: enableRecoveryInspector,
    allowUserHomeRoot: true,
  );

  final registry = PersistentArtifactBackendRegistry(
    environmentContext: productionContext
        ? PersistentArtifactBackendEnvironmentContext.production
        : PersistentArtifactBackendEnvironmentContext.nonProduction,
  );

  SecureFilesystemBackendFactory.registerInto(
    registry,
    config,
    environmentContext: productionContext
        ? PersistentArtifactBackendEnvironmentContext.production
        : PersistentArtifactBackendEnvironmentContext.nonProduction,
  );

  final provider = PlatformPersistentArtifactProvider(
    policyRegistry: PersistentArtifactPolicyRegistry(registerDefaults: true),
    sourceResolver: PersistentArtifactSourceResolver(
      releaseEvidenceProvider: _NullReleaseEvidenceProvider(),
      releaseSupplyChainProvider: _NullReleaseSupplyChainProvider(),
      cicdIntegrationProvider: _NullCicdProvider(),
      cryptographicTrustProvider: _NullCryptographicTrustProvider(),
    ),
    store: InMemoryPersistentArtifactSnapshotStore(),
    backendRegistry: registry,
  );

  return FilesystemIntegrationStack(
    root: root,
    config: config,
    registry: registry,
    provider: provider,
  );
}

void cleanupFilesystemStack(FilesystemIntegrationStack stack) {
  if (stack.root.existsSync()) {
    stack.root.deleteSync(recursive: true);
  }
}
