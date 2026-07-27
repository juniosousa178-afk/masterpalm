import 'package:masterpalm_platform/interfaces/cryptographic_trust_provider.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_evaluation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_query.dart';
import 'package:masterpalm_platform/models/history/history_artifact_type.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust integration surfaces', () {
    late CryptographicTrustTestStack stack;
    late CryptographicTrustProvider provider;

    setUp(() async {
      stack = CryptographicTrustOperationalFixtures.createTestStack();
      provider = stack.provider;
      await stack.registerTestKeys();
    });

    test('published snapshot exposes report-ready sections', () async {
      final published = await provider.evaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      final snapshot = published.snapshot!;
      expect(snapshot.subjects, isNotEmpty);
      expect(snapshot.digests, isNotEmpty);
      expect(snapshot.signatures, isNotEmpty);
      expect(snapshot.attestations, isNotEmpty);
      expect(snapshot.trustAnchors, isNotEmpty);
      expect(snapshot.trustChains, isNotEmpty);
      expect(snapshot.trustPolicies, isNotEmpty);
      expect(snapshot.revocations, isNotEmpty);
      expect(snapshot.transparencyLogReferences, isNotEmpty);
      expect(snapshot.sourceReferences, isNotEmpty);
      expect(snapshot.verificationResults, isNotEmpty);
    });

    test('snapshot json suitable for history artifact storage', () async {
      final published = await provider.evaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      final json = published.snapshot!.toJson();
      expect(json.containsKey('metadata'), isTrue);
      expect(json.containsKey('fingerprint'), isTrue);
      expect(json.containsKey('limitations'), isTrue);
      expect(
        json['limitations'],
        contains('no-release-authorization'),
      );
    });

    test('history artifact type enum includes cryptographicTrust', () {
      expect(
        HistoryArtifactType.values.map((e) => e.name),
        contains('cryptographicTrust'),
      );
    });

    test('evaluation result metadata is observability-safe', () async {
      final result = await provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.metadata.containsKey('noReleaseAuthorization'), isTrue);
      expect(result.toJson().containsKey('privateKey'), isFalse);
      expect(result.toJson().containsKey('signatureValue'), isFalse);
      expect(result.toJson().containsKey('payload'), isFalse);
    });

    test(
        'source resolver integration never increments upstream evaluate counters',
        () async {
      stack.releaseEvidenceProvider.loaded =
          ReleaseEvidenceTestFixtures.validBundle();
      await stack.sourceResolver.resolveAll(
        CryptographicTrustOperationalFixtures.evaluationRequest(
          useLatest: true,
          metadata: const {'releaseEvidenceBundleId': 'missing'},
        ),
        injectedTrustPolicy: stack.policyRegistry.resolve(
          policyId: 'artifact-signature-trust-v1',
          allowCandidate: true,
        ),
      );
      expect(stack.releaseEvidenceProvider.evaluateCalls, 0);
      expect(stack.releaseEvidenceProvider.evaluateAndPublishCalls, 0);
      expect(stack.releaseSupplyChainProvider.evaluateCalls, 0);
      expect(stack.cicdIntegrationProvider.evaluateCalls, 0);
    });

    test('dashboard-ready snapshot fields present without re-evaluation',
        () async {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      expect(snapshot.status, isA<CryptographicTrustStatus>());
      expect(snapshot.verificationResults, isNotEmpty);
      expect(
        snapshot.limitations.any((l) => l.contains('no-release-authorization')),
        isTrue,
      );
    });

    test('verified evaluation result does not authorize release in integration',
        () async {
      final result = await provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.verificationResult?.status, isNotNull);
      expect(result.toJson().containsKey('releaseAuthorized'), isFalse);
      expect(result.metadata['noReleaseAuthorization'], 'true');
    });

    test('query integration returns persisted snapshots only', () async {
      await provider.evaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      final snapshots = await provider.query(
        const CryptographicTrustQuery(
          projectId: CryptographicTrustOperationalFixtures.projectId,
        ),
      );
      expect(snapshots, hasLength(1));
    });

    test('load integration reads store without evaluate', () async {
      final published = await provider.evaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      stack.releaseEvidenceProvider.evaluateCalls = 0;
      final loaded = await provider.load(
        published.snapshot!.metadata.cryptographicTrustSnapshotId,
      );
      expect(loaded, isNotNull);
      expect(stack.releaseEvidenceProvider.evaluateCalls, 0);
    });

    test('partial evaluation surfaces partial operational status', () async {
      final result = await provider.evaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(
          metadata: const {'releaseEvidenceBundleId': 'missing-bundle'},
        ),
      );
      expect(
        result.sourceResolutionSummary?.status,
        CryptographicTrustSourceResolutionStatus.partial,
      );
    });
  });
}
