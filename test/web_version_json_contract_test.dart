import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/config/web_release_version_manifest.dart';

void main() {
  group('WEB_VERSION_JSON_PACKAGEINFO_CONTRACT_GUARDED', () {
    test('manifest completo valida contra HEAD pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = WebReleaseVersionManifest.fromPubspecAndGit(
        pubspecVersionLine: pubspec,
        buildId: 'test-build-id',
        gitCommit: 'abc1234',
      );
      expect(m.version, isNotEmpty);
      expect(m.buildNumber, isNotEmpty);
      expect(int.parse(m.buildNumber), greaterThanOrEqualTo(284));
      m.validate(expectedGitCommit: 'abc1234');
    });

    test('deploy metadata only é detectado', () {
      final deployOnly = {
        'buildId': 'old',
        'gitCommit': '33137cf',
        'hostingTarget': 'masterpalm-58c46',
      };
      expect(WebReleaseVersionManifest.isDeployMetadataOnly(deployOnly), isTrue);
    });

    test('manifest com PackageInfo não é deploy-only', () {
      final full = WebReleaseVersionManifest.fromPubspecAndGit(
        pubspecVersionLine: File('pubspec.yaml').readAsStringSync(),
        buildId: 'b',
        gitCommit: 'c',
      ).toJson();
      expect(WebReleaseVersionManifest.isDeployMetadataOnly(full), isFalse);
    });

    test('round-trip JSON preserva build_number', () {
      final m = WebReleaseVersionManifest.fromPubspecAndGit(
        pubspecVersionLine: File('pubspec.yaml').readAsStringSync(),
        buildId: 'stable-test',
        gitCommit: 'deadbeef',
      );
      final decoded = WebReleaseVersionManifest.fromJson(
        jsonDecode(m.toJsonString()) as Map<String, dynamic>,
      );
      expect(decoded.buildNumber, m.buildNumber);
      expect(decoded.version, m.version);
    });
  });
}
