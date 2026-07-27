import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

class GuardianConfig {
  GuardianConfig({
    required this.criticalFiles,
    required this.criticalMethods,
    required this.domainTests,
    required this.documentationMatrix,
    required this.rules,
  });

  final List<CriticalFile> criticalFiles;
  final List<CriticalMethod> criticalMethods;
  final Map<String, List<String>> domainTests;
  final Map<String, List<String>> documentationMatrix;
  final Map<String, dynamic> rules;

  static GuardianConfig load(String repoRoot, {Paths? paths}) {
    final configDir =
        paths?.guardianConfigDir ?? Paths(repoRoot: repoRoot).guardianConfigDir;
    return GuardianConfig(
      criticalFiles:
          _loadCriticalFiles(p.join(configDir, 'critical_files.yaml')),
      criticalMethods:
          _loadCriticalMethods(p.join(configDir, 'critical_methods.yaml')),
      domainTests:
          _loadDomainTests(p.join(configDir, 'domain_test_matrix.yaml')),
      documentationMatrix:
          _loadDocMatrix(p.join(configDir, 'documentation_matrix.yaml')),
      rules: _loadYamlMap(p.join(configDir, 'guardian_rules.yaml')),
    );
  }

  static List<CriticalFile> _loadCriticalFiles(String path) {
    final doc = _loadYamlMap(path);
    final list = doc['critical_files'] as List<dynamic>? ?? [];
    return list.map((e) {
      final m = e as Map;
      return CriticalFile(
        path: m['path'] as String,
        lines: m['lines'] as int? ?? 0,
        domains: (m['domains'] as List<dynamic>? ?? []).cast<String>(),
      );
    }).toList();
  }

  static List<CriticalMethod> _loadCriticalMethods(String path) {
    final doc = _loadYamlMap(path);
    final list = doc['critical_methods'] as List<dynamic>? ?? [];
    return list.map((e) {
      final m = e as Map;
      return CriticalMethod(
        file: m['file'] as String,
        method: m['method'] as String,
        complexity: m['complexity'] as int? ?? 0,
        domains: (m['domains'] as List<dynamic>? ?? []).cast<String>(),
      );
    }).toList();
  }

  static Map<String, List<String>> _loadDomainTests(String path) {
    final doc = _loadYamlMap(path);
    final map = <String, List<String>>{};
    final domains = doc['domains'] as Map<dynamic, dynamic>? ?? {};
    for (final entry in domains.entries) {
      map[entry.key.toString()] = (entry.value as List<dynamic>).cast<String>();
    }
    return map;
  }

  static Map<String, List<String>> _loadDocMatrix(String path) {
    final doc = _loadYamlMap(path);
    final map = <String, List<String>>{};
    final triggers = doc['triggers'] as Map<dynamic, dynamic>? ?? {};
    for (final entry in triggers.entries) {
      map[entry.key.toString()] = (entry.value as List<dynamic>).cast<String>();
    }
    return map;
  }

  static Map<String, dynamic> _loadYamlMap(String path) {
    if (!File(path).existsSync()) return {};
    return (loadYaml(File(path).readAsStringSync()) as YamlMap)
        .cast<String, dynamic>();
  }
}

class CriticalFile {
  CriticalFile({
    required this.path,
    required this.lines,
    required this.domains,
  });

  final String path;
  final int lines;
  final List<String> domains;
}

class CriticalMethod {
  CriticalMethod({
    required this.file,
    required this.method,
    required this.complexity,
    required this.domains,
  });

  final String file;
  final String method;
  final int complexity;
  final List<String> domains;
}
