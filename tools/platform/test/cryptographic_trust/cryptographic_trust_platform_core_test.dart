import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/core/platform_core.dart';
import 'package:masterpalm_platform/interfaces/cryptographic_trust_provider.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_operational_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_query.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('PlatformCore cryptographic trust delegations', () {
    late PlatformCore core;

    setUp(() {
      core = PlatformBootstrap.forRepo(Directory.current.path);
    });

    test('platform bootstrap resolves CryptographicTrustProvider', () {
      expect(core.cryptographicTrust(), isA<CryptographicTrustProvider>());
    });

    test('cryptographicTrustEvaluate returns operational result', () async {
      final result = await core.cryptographicTrustEvaluate(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.status, isA<CryptographicTrustEvaluationStatus>());
      expect(result.metadata['noReleaseAuthorization'], 'true');
    });

    test('cryptographicTrustEvaluateAndPublish persists snapshot', () async {
      final result = await core.cryptographicTrustEvaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      expect(result.snapshot, isNotNull);
      final loaded = await core.cryptographicTrustLoad(
        result.snapshot!.metadata.cryptographicTrustSnapshotId,
      );
      expect(loaded, isNotNull);
    });

    test('cryptographicTrustLatest returns published snapshot for project',
        () async {
      await core.cryptographicTrustEvaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      final latest = await core.cryptographicTrustLatest(
        projectId: CryptographicTrustOperationalFixtures.projectId,
        releaseId: CryptographicTrustOperationalFixtures.releaseId,
      );
      expect(latest, isNotNull);
    });

    test('cryptographicTrustVerifySignature delegates to provider', () async {
      final stack = CryptographicTrustOperationalFixtures.createTestStack();
      await stack.registerTestKeys();
      final payload = CryptographicTrustOperationalFixtures.payloadAbc;
      final envelope =
          await CryptographicTrustOperationalFixtures.signedEnvelope(payload);
      final result = await core.cryptographicTrustVerifySignature(
        envelope: envelope,
        subjectBytes: payload,
        projectId: CryptographicTrustOperationalFixtures.projectId,
      );
      expect(result, isNotNull);
    });

    test('cryptographicTrustQuery returns snapshots from provider store',
        () async {
      await core.cryptographicTrustEvaluateAndPublish(
        CryptographicTrustOperationalFixtures.evaluationRequest(),
      );
      final snapshots = await core.cryptographicTrustQuery(
        const CryptographicTrustQuery(
          projectId: CryptographicTrustOperationalFixtures.projectId,
        ),
      );
      expect(snapshots, isNotEmpty);
    });

    test('cryptographicTrustPublish stores snapshot directly', () async {
      final snapshot = CryptographicTrustTestFixtures.validSnapshot();
      await core.cryptographicTrustPublish(snapshot);
      final loaded = await core.cryptographicTrustLoad(
        snapshot.metadata.cryptographicTrustSnapshotId,
      );
      expect(loaded?.fingerprint, snapshot.fingerprint);
    });
  });
}
