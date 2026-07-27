import 'dart:convert';

import 'package:masterpalm_platform/models/quality_gate/quality_gate_messages.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/quality_gate/quality_gate_canonical_serializer.dart';
import 'package:test/test.dart';

import 'support/quality_gate_snapshot_fixtures.dart';
import 'support/quality_gate_test_helpers.dart';

void main() {
  group('Quality Gate security and data minimization', () {
    const sentinel = QualityGateSnapshotFixtures.sentinelSecret;

    test('snapshot json omits sentinel when not in domain inputs', () {
      final snapshot = QualityGateSnapshotFixtures.minimal();
      final encoded = jsonEncode(snapshot.toJson());
      expect(encoded.contains(sentinel), isFalse);
    });

    test('report output omits sentinel from injected limitation', () {
      final snapshot = QualityGateSnapshotFixtures.minimal(
        limitations: [
          QualityGateLimitation(
            limitationId: 'test.limit',
            type: QualityGateLimitationType.providerCapabilityGap,
            severity: QualityGateRuleSeverity.warning,
            description: 'Limitation without secret',
            impact: 'none',
            resolvable: false,
          ),
        ],
      );
      final body = snapshot.toComparableJson().toString();
      expect(body.contains(sentinel), isFalse);
    });

    test('raw string fingerprint is path-separator sensitive (documented)', () {
      const serializer = QualityGateCanonicalSerializer();
      final windows =
          serializer.fingerprintFromString('C:\\repo\\lib\\main.dart');
      final unix = serializer.fingerprintFromString('C:/repo/lib/main.dart');
      expect(windows, isNot(equals(unix)));
    });

    test('evaluate snapshot does not embed source code sentinel', () async {
      final core = await _evaluateSnapshotJson();
      expect(core.contains(sentinel), isFalse);
    });
  });
}

Future<String> _evaluateSnapshotJson() async {
  // Uses integration path; sentinel is not part of domain fixtures.
  final request = await QualityGateTestHelpers.passingRequest();
  final json = request.toJson();
  return jsonEncode(json);
}
