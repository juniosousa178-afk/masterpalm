import 'dart:io';

import 'package:path/path.dart' as p;

/// Portable path resolution for Guardian tests (independent of temp kernel paths).
class GuardianTestPaths {
  GuardianTestPaths._();

  static String? _guardianRoot;
  static String? _platformRoot;

  static String guardianPackageRoot() {
    return _guardianRoot ??= _findGuardianPackageRoot();
  }

  static String platformPackageRoot() {
    return _platformRoot ??=
        p.normalize(p.join(guardianPackageRoot(), '..', 'platform'));
  }

  static String repoRoot() {
    return p.normalize(p.join(guardianPackageRoot(), '..', '..'));
  }

  static bool _isGuardianPubspec(File pubspec) {
    if (!pubspec.existsSync()) {
      return false;
    }
    return RegExp(
      r'^name:\s*masterpalm_guardian\s*$',
      multiLine: true,
    ).hasMatch(pubspec.readAsStringSync());
  }

  static String _findGuardianPackageRoot() {
    final checked = <String>{};

    String? found;

    void check(String candidate) {
      final normalized = p.normalize(candidate);
      if (checked.contains(normalized)) {
        return;
      }
      checked.add(normalized);
      final pubspec = File(p.join(normalized, 'pubspec.yaml'));
      if (_isGuardianPubspec(pubspec)) {
        found = normalized;
      }
    }

    var dir = Directory.current;
    while (found == null) {
      check(dir.path);
      check(p.join(dir.path, 'tools', 'guardian'));
      if (found != null) {
        break;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }

    if (found == null) {
      throw StateError(
        'masterpalm_guardian package root not found from cwd=${Directory.current.path}',
      );
    }
    return found!;
  }
}
