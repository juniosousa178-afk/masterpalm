import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

void main() {
  group('status mapping audit', () {
    test('filesystem outcomes are mapped', () {
      expect(
        PersistentArtifactPhysicalStatusMapper.fromFilesystemOutcome(
          SecureFilesystemBackendOutcome.succeeded,
        ),
        PersistentArtifactPhysicalOperationStatus.succeeded,
      );
      expect(
        PersistentArtifactPhysicalStatusMapper.fromFilesystemOutcome(
          SecureFilesystemBackendOutcome.notFound,
        ),
        PersistentArtifactPhysicalOperationStatus.notFound,
      );
    });

    test('issue codes are mapped', () {
      expect(
        PersistentArtifactPhysicalStatusMapper.fromIssueCode('quarantined'),
        PersistentArtifactPhysicalOperationStatus.quarantined,
      );
      expect(
        PersistentArtifactPhysicalStatusMapper.fromIssueCode(
            'backend-disabled'),
        PersistentArtifactPhysicalOperationStatus.backendDisabled,
      );
    });
  });
}
