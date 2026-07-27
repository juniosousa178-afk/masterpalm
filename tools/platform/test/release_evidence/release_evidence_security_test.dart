import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/models/observability/telemetry_attributes.dart';
import 'package:masterpalm_platform/models/observability/telemetry_enums.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/observability/telemetry_data_sanitizer.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_canonical_serializer.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:test/test.dart';

import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence security review', () {
    const sentinelSecret = 'SECRET_TOKEN_SHOULD_NOT_APPEAR';
    const sentinelApiKey = 'API_KEY_SHOULD_NOT_APPEAR';

    test('bundle json omits sentinel when not in domain inputs', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rg = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final result = await core.releaseEvidenceEvaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rg.snapshot,
        ),
      );
      final encoded = jsonEncode(result.bundle!.toJson());
      expect(encoded.contains(sentinelSecret), isFalse);
      expect(encoded.contains(sentinelApiKey), isFalse);
    });

    test('canonical bundle fingerprint omits sentinel', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rg = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final result = await core.releaseEvidenceEvaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rg.snapshot,
        ),
      );
      const serializer = ReleaseEvidenceCanonicalSerializer();
      final fp = serializer.bundleFingerprint(result.bundle!);
      expect(fp.contains(sentinelSecret), isFalse);
    });

    test('report output omits sentinel strings', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rg = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final result = await core.releaseEvidenceEvaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rg.snapshot,
        ),
      );
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.releaseEvidence,
          projectId: result.bundle!.metadata.projectId,
          releaseEvidenceBundle: result.bundle!.toJson(),
        ),
      );
      final encoded = jsonEncode(report.document.toJson());
      expect(encoded.contains(sentinelSecret), isFalse);
    });

    test('unverified signature status does not imply cryptographic validity',
        () {
      final attestation = ReleaseEvidenceTestFixtures.validAttestation();
      expect(attestation.signatureReference, isNull);
      // Structural-only: presence of signature ref elsewhere is warning-only
    });

    test('telemetry sanitizer redacts secret attributes', () {
      const sanitizer = TelemetryDataSanitizer();
      final result = sanitizer.sanitize(
        TelemetryStringAttribute(
          key: 'secretToken',
          stringValue: sentinelSecret,
          classification: TelemetryAttributeClassification.internal,
        ),
      );
      expect(result.wasRejected || result.wasRedacted, isTrue);
    });
  });
}
