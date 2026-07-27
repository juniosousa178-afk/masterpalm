import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/report/sources/cryptographic_trust_report_source.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_hardening_helpers.dart';

void main() {
  group('Cryptographic Trust report audit', () {
    test('report source sanitizes snapshot without private keys', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      const source = CryptographicTrustReportSource();
      final data = source.fromSnapshot(snapshot);
      expect(data.snapshotId, snapshot.metadata.cryptographicTrustSnapshotId);
      expect(data.fingerprint, snapshot.fingerprint);
    });

    test('report engine generates cryptographicTrust report', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.cryptographicTrust,
          projectId: snapshot.metadata.projectId,
          cryptographicTrustSnapshot: snapshot.toJson(),
        ),
      );
      expect(report.document.sections, isNotEmpty);
      expect(
        report.document.metadata.reportType,
        ReportType.cryptographicTrust,
      );
    });

    test('report input excludes signature values', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      const source = CryptographicTrustReportSource();
      final data = source.fromSnapshot(snapshot);
      expect(data.signatureSummaries, isNotEmpty);
      for (final summary in data.signatureSummaries) {
        expect(summary.contains('privateKey'), isFalse);
      }
    });

    test('report source fromMap roundtrip preserves snapshot id', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      const source = CryptographicTrustReportSource();
      final fromMap = source.fromMap(snapshot.toJson());
      expect(
          fromMap.snapshotId, snapshot.metadata.cryptographicTrustSnapshotId);
    });
  });
}
