import 'package:masterpalm_platform/masterpalm_platform.dart';

PersistentArtifactSubject fixtureSubject([int index = 0]) {
  return PersistentArtifactSubject(
    subjectId: 'subject-$index',
    artifactType: PersistentArtifactType.report,
    projectId: 'proj-a',
    releaseId: 'rel-a',
    sourceModule: 'report',
    sourceId: 'source-$index',
    sourceFingerprint: 'fp-$index',
    contentType: 'application/json',
    schemaVersion: '1',
  );
}

PersistentArtifactOperationRequest fixtureOperationRequest({
  String requestId = 'req-1',
  List<PersistentArtifactSubject>? subjects,
}) {
  return PersistentArtifactOperationRequest(
    requestId: requestId,
    operationType: PersistentArtifactOperationType.persist,
    projectId: 'proj-a',
    releaseId: 'rel-a',
    artifactSubjects: subjects ?? [fixtureSubject()],
    requestedAt: '2026-07-22T00:00:00Z',
  );
}

PersistentArtifactEvaluationRequest fixtureEvaluationRequest({
  String evaluationId = 'eval-1',
  bool allowCandidate = true,
  bool useLatest = true,
  Map<String, String> metadata = const {},
}) {
  return PersistentArtifactEvaluationRequest(
    evaluationId: evaluationId,
    projectId: 'proj-a',
    releaseId: 'rel-a',
    requestedAt: '2026-07-22T00:00:00Z',
    operationRequest: fixtureOperationRequest(),
    allowCandidate: allowCandidate,
    useLatest: useLatest,
    metadata: metadata,
  );
}
