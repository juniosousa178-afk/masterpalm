import 'dart:convert';

import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../../models/report/report_document.dart';
import '../history_canonical_serializer.dart';

/// Maps [ReportDocument] to [HistoryArtifact].
class ReportHistoryMapper {
  const ReportHistoryMapper({HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final document = ReportDocument.fromJson(json);
    final fingerprint = _serializer.fingerprintFromString(
      jsonEncode(document.toComparableJson()),
    );
    return HistoryArtifact(
      artifactType: HistoryArtifactType.report,
      artifactId: document.metadata.reportId,
      schemaVersion: document.metadata.reportSchemaVersion,
      fingerprint: fingerprint,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: document.toJson(),
      ),
    );
  }
}
