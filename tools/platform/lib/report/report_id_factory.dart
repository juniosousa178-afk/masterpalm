import '../models/report/report_type.dart';

/// Deterministic report identity factory.
class ReportIdFactory {
  const ReportIdFactory();

  String create({
    required String projectId,
    required ReportType reportType,
    required String sourceFingerprint,
  }) {
    return 'report:$projectId:${reportType.wireName}:$sourceFingerprint';
  }

  String fingerprintFromParts(List<String> parts) {
    final normalized =
        parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList()..sort();
    return normalized.join('|');
  }
}
