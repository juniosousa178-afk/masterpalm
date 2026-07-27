import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/secure_filesystem_test_helpers.dart';

void main() {
  group('SecureFilesystemBackendConfigValidator', () {
    test('accepts valid config', () {
      final dir = createTempSandbox('cfg-ok');
      addTearDown(() => dir.deleteSync(recursive: true));
      final errors =
          SecureFilesystemBackendConfigValidator.validate(buildConfig(dir));
      expect(errors, isEmpty);
    });

    test('rejects empty backend id', () {
      final dir = createTempSandbox('cfg-backend');
      addTearDown(() => dir.deleteSync(recursive: true));
      final config = SecureFilesystemBackendConfig(
        backendId: ' ',
        rootDirectory: dir.path,
        maximumContentSizeBytes: 1,
        allowUserHomeRoot: true,
      );
      expect(
        SecureFilesystemBackendConfigValidator.validate(config),
        isNotEmpty,
      );
    });

    test('rejects relative root', () {
      final config = SecureFilesystemBackendConfig(
        backendId: 'id',
        rootDirectory: 'relative/root',
        maximumContentSizeBytes: 1,
      );
      expect(
        SecureFilesystemBackendConfigValidator.validate(config).join(' '),
        contains('absolute'),
      );
    });

    test('rejects filesystem root', () {
      final root = Platform.isWindows ? r'C:\' : '/';
      final config = SecureFilesystemBackendConfig(
        backendId: 'id',
        rootDirectory: root,
        maximumContentSizeBytes: 1,
      );
      expect(
        SecureFilesystemBackendConfigValidator.validate(config).join(' '),
        contains('filesystem root'),
      );
    });

    test('rejects size <= 0', () {
      final dir = createTempSandbox('cfg-size');
      addTearDown(() => dir.deleteSync(recursive: true));
      final config = SecureFilesystemBackendConfig(
        backendId: 'id',
        rootDirectory: dir.path,
        maximumContentSizeBytes: 0,
        allowUserHomeRoot: true,
      );
      expect(
        SecureFilesystemBackendConfigValidator.validate(config).join(' '),
        contains('> 0'),
      );
    });

    for (final invalidName in const [
      '',
      ' ',
      '../bad',
      r'..\bad',
      r'a\b',
      'a/b',
    ]) {
      test('rejects invalid directory name "$invalidName"', () {
        final dir = createTempSandbox('cfg-dir-name');
        addTearDown(() => dir.deleteSync(recursive: true));
        final config = SecureFilesystemBackendConfig(
          backendId: 'id',
          rootDirectory: dir.path,
          maximumContentSizeBytes: 1,
          allowUserHomeRoot: true,
          contentDirectoryName: invalidName,
        );
        expect(
          SecureFilesystemBackendConfigValidator.validate(config).join(' '),
          contains('directory'),
        );
      });
    }
  });
}
