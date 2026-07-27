import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/models/observability/telemetry_attributes.dart';
import 'package:masterpalm_platform/models/observability/telemetry_enums.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/observability/telemetry_data_sanitizer.dart';
import 'package:masterpalm_platform/release_governance/release_governance_canonical_serializer.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:test/test.dart';

import 'support/release_governance_test_fixtures.dart';

void main() {
  group('Release Governance security and data minimization', () {
    const sentinelSecret = 'SECRET_TOKEN_SHOULD_NOT_APPEAR';
    const sentinelApiKey = 'API_KEY_SHOULD_NOT_APPEAR';
    const sentinelPassword = 'PASSWORD_SHOULD_NOT_APPEAR';

    test('snapshot json omits sentinel when not in domain inputs', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final result = await core.releaseGovernanceEvaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final encoded = jsonEncode(result.snapshot!.toJson());
      expect(encoded.contains(sentinelSecret), isFalse);
      expect(encoded.contains(sentinelApiKey), isFalse);
      expect(encoded.contains(sentinelPassword), isFalse);
    });

    test('canonical comparable snapshot omits sentinel from structural fields',
        () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final result = await core.releaseGovernanceEvaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      const serializer = ReleaseGovernanceCanonicalSerializer();
      final comparable = jsonEncode(
        serializer.snapshotFingerprint(result.snapshot!),
      );
      expect(comparable.contains(sentinelSecret), isFalse);
    });

    test('report output omits sentinel strings', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final evaluation = await core.releaseGovernanceEvaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.releaseGovernance,
          projectId: evaluation.snapshot!.metadata.projectId,
          releaseDecisionSnapshot: evaluation.snapshot!.toJson(),
        ),
      );
      final encoded = jsonEncode(report.document.toJson());
      expect(encoded.contains(sentinelSecret), isFalse);
      expect(encoded.contains(sentinelApiKey), isFalse);
      expect(encoded.contains(sentinelPassword), isFalse);
    });

    test('telemetry sanitizer redacts prohibited secret attribute values', () {
      const sanitizer = TelemetryDataSanitizer();
      final result = sanitizer.sanitize(
        TelemetryStringAttribute(
          key: 'secretToken',
          stringValue: sentinelSecret,
          classification: TelemetryAttributeClassification.internal,
        ),
      );
      expect(result.wasRejected || result.wasRedacted, isTrue);
      if (result.attribute != null) {
        expect(result.attribute!.value?.toString().contains(sentinelSecret),
            isFalse);
      }
    });

    test('telemetry sanitizer rejects snapshot payload keys', () {
      const sanitizer = TelemetryDataSanitizer();
      expect(
        () => sanitizer.sanitizeAll([
          TelemetryStringAttribute(
            key: 'snapshotPayload',
            stringValue: sentinelSecret,
            classification: TelemetryAttributeClassification.internal,
          ),
        ]),
        throwsA(isA<Exception>()),
      );
    });

    test('request json does not embed sentinel from fixtures', () {
      final encoded = jsonEncode(
        ReleaseGovernanceTestFixtures.passingRequest().toJson(),
      );
      expect(encoded.contains(sentinelSecret), isFalse);
      expect(encoded.contains(sentinelApiKey), isFalse);
    });
  });
}
