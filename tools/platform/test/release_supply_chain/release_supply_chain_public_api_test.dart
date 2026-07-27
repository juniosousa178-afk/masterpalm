import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('Release Supply Chain public API review', () {
    test('core provider types are exported', () {
      expect(ReleaseSupplyChainProvider, isNotNull);
      expect(ReleaseSupplyChainStore, isNotNull);
      expect(InMemoryReleaseSupplyChainStore, isNotNull);
      expect(PlatformReleaseSupplyChainProvider, isNotNull);
    });

    test('bootstrap is exported', () {
      expect(ReleaseSupplyChainPlatformBootstrap, isNotNull);
    });

    test('operational models are exported', () {
      expect(ReleaseSupplyChainSnapshot, isNotNull);
      expect(ReleaseSupplyChainRequest, isNotNull);
      expect(ReleaseSupplyChainResult, isNotNull);
      expect(ReleaseSupplyChainQuery, isNotNull);
    });

    test('snapshot metadata schema versions are accessible', () {
      expect(ReleaseSupplyChainSnapshotMetadata.currentSchemaVersion,
          greaterThan(0));
      expect(
        ReleaseSupplyChainSnapshotMetadata.currentCanonicalizationVersion,
        greaterThan(0),
      );
    });
  });
}
