import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/secure_filesystem_test_helpers.dart';

void main() {
  group('SecureFilesystemManifestStore', () {
    late Directory root;
    late SecureFilesystemManifestStore store;

    setUp(() {
      root = createTempSandbox('manifest-store');
      final backend = SecureFilesystemBackendFactory.create(buildConfig(root));
      store = backend.manifestStore as SecureFilesystemManifestStore;
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    test('save and load by manifest id', () async {
      final m = manifest();
      await store.saveManifest(m);
      final loaded = await store.loadManifest(m.manifestId);
      expect(loaded, isNotNull);
      expect(loaded!.artifactId, m.artifactId);
    });

    test('save is idempotent for same payload', () async {
      final m = manifest();
      final one = await store.saveManifestWithResult(m);
      final two = await store.saveManifestWithResult(m);
      expect(one.outcome, SecureFilesystemBackendOutcome.succeeded);
      expect(two.idempotent, isTrue);
    });

    test('returns conflict for changed payload same location', () async {
      final m = manifest(versionId: 'v1');
      await store.saveManifest(m);
      final changed = m.copyWith(createdAt: '2026-02-02T00:00:00Z');
      final result = await store.saveManifestWithResult(changed);
      expect(result.outcome, SecureFilesystemBackendOutcome.conflict);
    });

    test('latest returns most recent by createdAt', () async {
      await store.saveManifest(
        manifest(
            manifestId: 'm1',
            versionId: 'v1',
            createdAt: '2026-01-01T00:00:00Z'),
      );
      await store.saveManifest(
        manifest(
            manifestId: 'm2',
            versionId: 'v2',
            createdAt: '2026-03-01T00:00:00Z'),
      );
      final latest = await store.latest(artifactId: 'artifact-1');
      expect(latest!.versionId, 'v2');
    });

    test('query filters by project/release/artifact', () async {
      await store.saveManifest(manifest(manifestId: 'ma', artifactId: 'a'));
      await store.saveManifest(
        manifest(
          manifestId: 'mb',
          artifactId: 'b',
          customSubject: subject(projectId: 'other', releaseId: 'other'),
        ),
      );
      final matches = await store.query(
        const PersistentArtifactQuery(projectId: 'proj-1', artifactId: 'a'),
      );
      expect(matches.length, 1);
      expect(matches.first.artifactId, 'a');
    });

    for (var i = 0; i < 18; i++) {
      test('list/query pagination case ${i + 1}', () async {
        final m = manifest(
          manifestId: 'm-$i',
          artifactId: 'artifact-$i',
          versionId: 'v$i',
          createdAt: '2026-01-${(i % 28) + 1}T00:00:00Z',
        );
        await store.saveManifest(m);
        final list = await store.list();
        expect(list, isNotEmpty);
        final queried = await store
            .query(const PersistentArtifactQuery(limit: 5, offset: 0));
        expect(queried.length, inInclusiveRange(1, 5));
      });
    }

    test('invalidate removes manifest', () async {
      final m = manifest(manifestId: 'gone', versionId: 'v-gone');
      await store.saveManifest(m);
      await store.invalidate('gone');
      expect(await store.loadManifest('gone'), isNull);
    });
  });
}
