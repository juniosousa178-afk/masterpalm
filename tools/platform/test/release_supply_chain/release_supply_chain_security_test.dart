import 'dart:convert';

import 'package:masterpalm_platform/models/observability/telemetry_attributes.dart';
import 'package:masterpalm_platform/models/observability/telemetry_enums.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/observability/telemetry_data_sanitizer.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_canonical_serializer.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_hardening_helpers.dart';
import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release Supply Chain security review', () {
    const sentinelSecret = 'SECRET_TOKEN_SHOULD_NOT_APPEAR';
    const sentinelApiKey = 'API_KEY_SHOULD_NOT_APPEAR';

    test('snapshot json omits sentinel when not in domain inputs', () async {
      final result = await evaluatePassingSnapshot();
      final encoded = jsonEncode(result.snapshot!.toJson());
      expect(encoded.contains(sentinelSecret), isFalse);
      expect(encoded.contains(sentinelApiKey), isFalse);
    });

    test('canonical snapshot fingerprint omits sentinel', () async {
      final result = await evaluatePassingSnapshot();
      const serializer = ReleaseSupplyChainCanonicalSerializer();
      final fp = serializer.snapshotFingerprint(result.snapshot!);
      expect(fp.contains(sentinelSecret), isFalse);
    });

    test('report output omits sentinel strings', () async {
      final result = await evaluatePassingSnapshot();
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.releaseSupplyChain,
          projectId: result.snapshot!.metadata.projectId,
          releaseSupplyChainSnapshot: result.snapshot!.toJson(),
        ),
      );
      final encoded = jsonEncode(report.document.toJson());
      expect(encoded.contains(sentinelSecret), isFalse);
    });

    test('sha256 placeholders are sentinel strings not crypto claims', () {
      expect(
        ReleaseSupplyChainTestFixtures.sha256PlaceholderA,
        hasLength(64),
      );
      expect(
        ReleaseSupplyChainTestFixtures.validArtifactRecord()
            .integrity
            .digest
            .value,
        ReleaseSupplyChainTestFixtures.sha256PlaceholderB,
      );
    });

    test('no cryptographic verification is assumed in snapshot limitations',
        () async {
      final result = await evaluatePassingSnapshot();
      final limitations = result.snapshot?.metadata.limitations ?? const [];
      expect(
        limitations.any((l) => l.contains('no-cryptographic-verification')),
        isTrue,
      );
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
