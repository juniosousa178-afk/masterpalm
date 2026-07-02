import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _demoProjectId = 'demo-masterpalm-pdv-v1-r1';

void main() {
  group('PDV V1 R1 — marker rules scope guard', () {
    late String runnerSource;
    late String rulesSource;

    setUpAll(() {
      final repoRoot = Directory.current.path;
      runnerSource = File(
        '$repoRoot/test/pdv_v1_rules_v1/support/pdv_v1_marker_rules_v1_runner.mjs',
      ).readAsStringSync();
      rulesSource = File('$repoRoot/firestore.rules').readAsStringSync();
    });

    test('runner usa projectId demo-masterpalm-pdv-v1-r1', () {
      expect(runnerSource, contains(_demoProjectId));
    });

    test('runner rejeita host externo e masterpalm-58c46', () {
      expect(runnerSource, contains('masterpalm-58c46'));
      expect(runnerSource, contains('isLocalEmulatorHost'));
      expect(runnerSource, contains('ABORT'));
    });

    test('runner usa @firebase/rules-unit-testing sem firebase-admin', () {
      expect(runnerSource, contains('@firebase/rules-unit-testing'));
      expect(runnerSource, isNot(contains("from 'firebase-admin'")));
      expect(runnerSource, isNot(contains('from "firebase-admin"')));
      expect(runnerSource, isNot(contains("require('firebase-admin')")));
      expect(runnerSource, isNot(contains('require("firebase-admin")')));
    });

    test('runner não inicia emulator nem deploy', () {
      expect(runnerSource, isNot(contains('emulators:start')));
      expect(runnerSource, isNot(contains('firebase deploy')));
    });

    test('runner não contém URL remota http/https', () {
      expect(runnerSource, isNot(contains('http://')));
      expect(runnerSource, isNot(contains('https://')));
    });

    test('firestore.rules contém bloco V1 identificável', () {
      expect(rulesSource, contains('isV1MarkerCreate'));
      expect(rulesSource, contains('hasExactV1MarkerKeys'));
      expect(rulesSource, contains('protocolVersion'));
      expect(rulesSource, contains('estoque_baixa_pagamento/{markerId}'));
    });

    test('sem referência R1 nova em lib ou harness', () {
      final repoRoot = Directory.current.path;
      final libHits = _grepInTree(
        Directory('$repoRoot/lib'),
        'pdv_v1_marker_rules_v1',
      );
      final harnessHits = _grepInTree(
        Directory('$repoRoot/test/pdv_v1_harness'),
        'pdv_v1_marker_rules_v1',
      );
      final demoHitsLib = _grepInTree(
        Directory('$repoRoot/lib'),
        _demoProjectId,
      );
      final demoHitsHarness = _grepInTree(
        Directory('$repoRoot/test/pdv_v1_harness'),
        _demoProjectId,
      );
      expect(libHits, isEmpty);
      expect(harnessHits, isEmpty);
      expect(demoHitsLib, isEmpty);
      expect(demoHitsHarness, isEmpty);
    });
  });
}

List<String> _grepInTree(Directory root, String needle) {
  if (!root.existsSync()) return const [];
  final hits = <String>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (path.contains('test/pdv_v1_rules_v1/')) continue;
    try {
      if (entity.readAsStringSync().contains(needle)) {
        hits.add(path);
      }
    } catch (_) {
      // binário ou ilegível — ignorar
    }
  }
  return hits;
}
