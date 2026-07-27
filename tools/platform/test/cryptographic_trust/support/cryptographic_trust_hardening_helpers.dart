import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_exceptions.dart';
import 'package:test/test.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_snapshot.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_request.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/resolved_cryptographic_trust_sources.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_snapshot.dart';

import '../../release_evidence/support/release_evidence_test_fixtures.dart';
import '../../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'cryptographic_trust_operational_fixtures.dart';
import 'cryptographic_trust_test_fixtures.dart';

/// Builds a deterministic passing Cryptographic Trust evaluation via test stack.
Future<CryptographicTrustEvaluationResult> evaluatePassingSnapshot({
  CryptographicTrustTestStack? stack,
  bool registerKeys = true,
}) async {
  final resolved =
      stack ?? CryptographicTrustOperationalFixtures.createTestStack();
  if (registerKeys) {
    await resolved.registerTestKeys();
  }
  return resolved.provider.evaluate(
    CryptographicTrustOperationalFixtures.evaluationRequest(),
  );
}

/// Builds and publishes a deterministic passing Cryptographic Trust snapshot.
Future<CryptographicTrustEvaluationResult> publishPassingSnapshot({
  CryptographicTrustTestStack? stack,
  bool registerKeys = true,
}) async {
  final resolved =
      stack ?? CryptographicTrustOperationalFixtures.createTestStack();
  if (registerKeys) {
    await resolved.registerTestKeys();
  }
  return resolved.provider.evaluateAndPublish(
    CryptographicTrustOperationalFixtures.evaluationRequest(),
  );
}

ResolvedCryptographicTrustSource<T> ctNotRequested<T>(
  CryptographicSourceType sourceType,
) {
  return ResolvedCryptographicTrustSource<T>(
    sourceType: sourceType,
    resolutionMode: CryptographicTrustSourceResolutionMode.notRequested,
    state: CryptographicTrustSourceState.notRequested,
  );
}

/// Verified scenario: full upstream context with valid signed material.
Future<CryptographicTrustEvaluationResult> evaluateVerifiedScenario({
  CryptographicTrustTestStack? stack,
}) async {
  final resolved =
      stack ?? CryptographicTrustOperationalFixtures.createTestStack();
  await resolved.registerTestKeys();
  final envelope = await CryptographicTrustOperationalFixtures.signedEnvelope(
    CryptographicTrustOperationalFixtures.payloadAbc,
  );
  return resolved.provider.evaluate(
    CryptographicTrustOperationalFixtures.evaluationRequest(
      verificationRequest:
          CryptographicTrustOperationalFixtures.verificationRequest(
        signatures: [envelope],
      ),
      releaseEvidenceBundle: ReleaseEvidenceTestFixtures.validBundle(),
      releaseSupplyChainSnapshot:
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot(),
    ),
  );
}

/// Partial scenario: optional upstream sources unresolved.
Future<CryptographicTrustEvaluationResult> evaluatePartialScenario({
  CryptographicTrustTestStack? stack,
}) async {
  final resolved =
      stack ?? CryptographicTrustOperationalFixtures.createTestStack();
  await resolved.registerTestKeys();
  return resolved.provider.evaluate(
    CryptographicTrustOperationalFixtures.evaluationRequest(
      metadata: const {'releaseEvidenceBundleId': 'missing-bundle'},
    ),
  );
}

/// Failed scenario: tampered signature in verification request.
Future<CryptographicTrustEvaluationResult> evaluateFailedScenario({
  CryptographicTrustTestStack? stack,
}) async {
  final resolved =
      stack ?? CryptographicTrustOperationalFixtures.createTestStack();
  await resolved.registerTestKeys();
  final envelope = await CryptographicTrustOperationalFixtures.signedEnvelope(
    CryptographicTrustOperationalFixtures.payloadAbc,
  );
  return resolved.provider.evaluate(
    CryptographicTrustOperationalFixtures.evaluationRequest(
      verificationRequest:
          CryptographicTrustOperationalFixtures.verificationRequest(
        signatures: [envelope.copyWith(signatureValue: 'AAAA')],
      ),
    ),
  );
}

/// Conflicting scenario: publishes snapshot then attempts status mutation publish.
Future<CryptographicTrustSnapshotConflictException> publishConflictingScenario({
  CryptographicTrustTestStack? stack,
}) async {
  final resolved =
      stack ?? CryptographicTrustOperationalFixtures.createTestStack();
  final snapshot = CryptographicTrustTestFixtures.validSnapshot();
  await resolved.provider.publish(snapshot);
  try {
    await resolved.provider.publish(
      snapshot.copyWith(status: CryptographicTrustStatus.invalid),
    );
    throw StateError('expected CryptographicTrustSnapshotConflictException');
  } on CryptographicTrustSnapshotConflictException catch (e) {
    return e;
  }
}

/// Builds evaluation request with injected upstream artifacts for replay tests.
CryptographicTrustEvaluationRequest verifiedScenarioRequest({
  ReleaseEvidenceBundle? releaseEvidenceBundle,
  ReleaseSupplyChainSnapshot? releaseSupplyChainSnapshot,
  CicdIntegrationSnapshot? cicdIntegrationSnapshot,
}) {
  return CryptographicTrustOperationalFixtures.evaluationRequest(
    releaseEvidenceBundle:
        releaseEvidenceBundle ?? ReleaseEvidenceTestFixtures.validBundle(),
    releaseSupplyChainSnapshot: releaseSupplyChainSnapshot ??
        ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot(),
    cicdIntegrationSnapshot: cicdIntegrationSnapshot,
  );
}

CryptographicTrustEvaluationRequest partialScenarioRequest() {
  return CryptographicTrustOperationalFixtures.evaluationRequest(
    metadata: const {'releaseEvidenceBundleId': 'missing-bundle'},
  );
}

Future<CryptographicVerificationRequest>
    failedScenarioVerificationRequest() async {
  final envelope = await CryptographicTrustOperationalFixtures.signedEnvelope(
    CryptographicTrustOperationalFixtures.payloadAbc,
  );
  return CryptographicTrustOperationalFixtures.verificationRequest(
    signatures: [envelope.copyWith(signatureValue: 'tampered')],
  );
}

CryptographicTrustSnapshot conflictingScenarioSnapshot({
  CryptographicTrustSnapshot? base,
}) {
  final snapshot = base ?? CryptographicTrustTestFixtures.validSnapshot();
  return snapshot.copyWith(status: CryptographicTrustStatus.invalid);
}

/// Shared golden assertion: create file if missing, compare normative keys only.
void assertCryptographicTrustGolden(
  String path,
  Map<String, dynamic> normative,
  List<String> keys,
) {
  final file = File(path);
  if (!file.existsSync()) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        '_note':
            'Intentional golden for Cryptographic Trust. Update explicitly only.',
        ...normative,
      }),
    );
  }
  final golden = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  for (final key in keys) {
    expect(normative[key], golden[key], reason: 'golden key: $key');
  }
}
