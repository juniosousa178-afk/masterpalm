import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('CI/CD Integration public API review', () {
    test('core provider types are exported', () {
      expect(CicdIntegrationProvider, isNotNull);
      expect(CicdIntegrationStore, isNotNull);
      expect(InMemoryCicdIntegrationStore, isNotNull);
      expect(PlatformCicdIntegrationProvider, isNotNull);
    });

    test('bootstrap is exported', () {
      expect(CicdIntegrationPlatformBootstrap, isNotNull);
    });

    test('operational models are exported', () {
      expect(CicdIntegrationSnapshot, isNotNull);
      expect(CicdIntegrationRequest, isNotNull);
      expect(CicdIntegrationResult, isNotNull);
      expect(CicdIntegrationQuery, isNotNull);
    });

    test('snapshot metadata schema versions are accessible', () {
      expect(
        CicdIntegrationSnapshotMetadata.currentSchemaVersion,
        greaterThan(0),
      );
      expect(
        CicdIntegrationSnapshotMetadata.currentCanonicalizationVersion,
        greaterThan(0),
      );
    });
  });
}
