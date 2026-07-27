import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_evidence.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/report/sources/quality_gate_report_source.dart';
import 'package:test/test.dart';

import 'support/quality_gate_snapshot_fixtures.dart';

void main() {
  const reportSource = QualityGateReportSource();

  group('Quality Gate Report', () {
    for (final decision in QualityGateDecision.values) {
      test('decision $decision produces report without engine', () async {
        final failed = decision == QualityGateDecision.failed
            ? [
                QualityGateSnapshotFixtures.evaluation(
                  ruleId: 'QG003',
                  status: QualityGateRuleStatus.failed,
                  severity: QualityGateRuleSeverity.critical,
                ),
              ]
            : <QualityGateEvaluation>[];
        final snapshot = QualityGateSnapshotFixtures.minimal(
          id: 'qg-report-$decision',
          fingerprint: 'fp-report-$decision',
          decision: decision,
          evaluations: failed,
        );

        final input = reportSource.fromSnapshot(snapshot);
        expect(input.decision, decision.wireName);
        expect(input.policyId, isNotEmpty);

        final engine = ReportEngine();
        final report = await engine.generate(
          ReportRequest(
            reportType: ReportType.qualityGate,
            projectId: snapshot.metadata.projectId,
            qualityGateSnapshot: snapshot.toJson(),
          ),
        );

        expect(report.document.metadata.reportType, ReportType.qualityGate);
        expect(report.document.sections, isNotEmpty);
        final body = report.document.toJson().toString();
        expect(body.contains('Quality Gate'), isTrue);
      });
    }

    test('failed rules include critical and warning rule ids', () {
      final snapshot = QualityGateSnapshotFixtures.minimal(
        decision: QualityGateDecision.failed,
        evaluations: [
          QualityGateSnapshotFixtures.evaluation(
            ruleId: 'QG-WARN',
            severity: QualityGateRuleSeverity.warning,
          ),
          QualityGateSnapshotFixtures.evaluation(
            ruleId: 'QG-CRIT',
            severity: QualityGateRuleSeverity.critical,
          ),
        ],
      );
      final input = reportSource.fromSnapshot(snapshot);
      expect(input.failedRules.length, 2);
      expect(
        input.failedRules.any((r) => r.contains('QG-CRIT')),
        isTrue,
      );
      expect(
        input.failedRules.any((r) => r.contains('QG-WARN')),
        isTrue,
      );
    });

    test('report ID is deterministic for same snapshot', () async {
      final snapshot = QualityGateSnapshotFixtures.minimal();
      final engine = ReportEngine();
      final request = ReportRequest(
        reportType: ReportType.qualityGate,
        projectId: snapshot.metadata.projectId,
        qualityGateSnapshot: snapshot.toJson(),
      );
      final a = await engine.generate(request);
      final b = await engine.generate(request);
      expect(
        a.document.metadata.reportId,
        b.document.metadata.reportId,
      );
    });
  });
}
