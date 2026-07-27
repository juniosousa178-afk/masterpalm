import 'package:masterpalm_platform/history/mappers/quality_gate_history_mapper.dart';
import 'package:masterpalm_platform/models/history/history_change_type.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:test/test.dart';

import 'support/quality_gate_snapshot_fixtures.dart';

void main() {
  const mapper = QualityGateHistoryMapper();

  group('QualityGateHistoryMapper', () {
    test('adapter produces valid artifact', () {
      final snapshot = QualityGateSnapshotFixtures.minimal();
      final artifact = mapper.fromMap(snapshot.toJson());
      expect(artifact.artifactType.name, 'qualityGate');
      expect(artifact.artifactId, snapshot.metadata.qualityGateSnapshotId);
      expect(artifact.fingerprint, isNotEmpty);
    });

    test('decision change produces diff', () {
      final from = QualityGateSnapshotFixtures.minimal(
        decision: QualityGateDecision.error,
      );
      final to = QualityGateSnapshotFixtures.minimal(
        id: 'qg-2',
        fingerprint: 'fp-2',
        decision: QualityGateDecision.failed,
      );
      final changes = mapper.compare(from, to);
      expect(changes.any((c) => c.subjectId == 'decision'), isTrue);
    });

    test('policy version change produces diff', () {
      final from = QualityGateSnapshotFixtures.minimal();
      final toJson = from.toJson();
      final meta = Map<String, dynamic>.from(
        toJson['metadata'] as Map<String, dynamic>,
      );
      meta['policyVersion'] = 2;
      toJson['metadata'] = meta;
      final to = QualityGateSnapshot.fromJson(toJson);
      final changes = mapper.compare(from, to);
      expect(changes.any((c) => c.subjectId == 'policyVersion'), isTrue);
    });

    test('coverage change produces metric diff', () {
      final from = QualityGateSnapshotFixtures.minimal();
      final toJson = from.toJson();
      final coverage = Map<String, dynamic>.from(
        toJson['coverage'] as Map<String, dynamic>,
      );
      coverage['requiredRuleCoveragePercentage'] = 50;
      toJson['coverage'] = coverage;
      final to = QualityGateSnapshot.fromJson(toJson);
      final changes = mapper.compare(from, to);
      expect(
        changes.any((c) => c.subjectId == 'requiredRuleCoveragePercentage'),
        isTrue,
      );
      expect(
        changes
            .firstWhere((c) => c.subjectId == 'requiredRuleCoveragePercentage')
            .changeType,
        HistoryChangeType.metricValueChanged,
      );
    });

    test('same snapshot produces empty diff', () {
      final snapshot = QualityGateSnapshotFixtures.minimal();
      expect(mapper.compare(snapshot, snapshot), isEmpty);
    });
  });
}
