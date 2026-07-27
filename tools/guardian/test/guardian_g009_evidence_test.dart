import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path_lib;
import 'package:test/test.dart';

import '../lib/guardian_evidence.dart';

void main() {
  late Directory tempDir;
  late String repoRoot;
  late String rulesPath;
  late String emulatorPath;
  late String readbackPath;

  const functionalSha =
      '76470c9517c5c2355ecb307435187e97a994f73694236cbee8eed06a2599680c';
  const baseHead = '17fb382f2eee598e5bf1dd55acba7f5e328dd4ab';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('g009_evidence_');
    repoRoot = tempDir.path;
    rulesPath = path_lib.join(repoRoot, 'firestore.rules');
    emulatorPath = path_lib.join(
        repoRoot, 'functions', 'test', 'rules-stock-revision-emulator.mjs');
    readbackPath = path_lib.join(
        repoRoot, 'functions', 'test', 'stock-revision-readback-emulator.mjs');
    await File(rulesPath).writeAsString('rules { match /d/{d} { allow read: if true; } }');
    await File(emulatorPath).create(recursive: true);
    await File(emulatorPath).writeAsString('// emulator');
    await File(readbackPath).create(recursive: true);
    await File(readbackPath).writeAsString('// readback');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  String sha(String path) =>
      sha256.convert(File(path).readAsBytesSync()).toString();

  Map<String, dynamic> baseEvidence({
    String? rulesHash,
    String? emulatorHash,
    String? readbackHash,
    int failed = 0,
    int exitCode = 0,
    String? functionalPatchSha,
    String? evidenceBaseHead,
    String? guardianPatchSha,
  }) {
    return {
      'schemaVersion': 1,
      'baseHead': evidenceBaseHead ?? baseHead,
      'functionalPatchSha256': functionalPatchSha ?? functionalSha,
      if (guardianPatchSha != null) 'guardianPatchSha256': guardianPatchSha,
      'command': 'npm run test:rules:stock',
      'workingDirectory': 'functions',
      'firestoreRulesSha256': (rulesHash ?? sha(rulesPath)).toLowerCase(),
      'testFiles': [
        {
          'path': 'functions/test/rules-stock-revision-emulator.mjs',
          'sha256': (emulatorHash ?? sha(emulatorPath)).toLowerCase(),
        },
        {
          'path': 'functions/test/stock-revision-readback-emulator.mjs',
          'sha256': (readbackHash ?? sha(readbackPath)).toLowerCase(),
        },
      ],
      'passed': 9,
      'failed': failed,
      'skipped': 0,
      'exitCode': exitCode,
    };
  }

  Future<String> writeEvidence(Map<String, dynamic> json) async {
    final path = path_lib.join(tempDir.path, 'guardian-evidence.json');
    await File(path).writeAsString(jsonEncode(json));
    return path;
  }

  test('G009-E1 evidência válida aceita', () {
    final path = path_lib.join(tempDir.path, 'ev-e1.json');
    File(path).writeAsStringSync(jsonEncode(baseEvidence()));
    final v = GuardianEvidenceValidator.validate(
      repoRoot: repoRoot,
      evidencePath: path,
      expectedFunctionalPatchSha256: functionalSha.toUpperCase(),
      expectedBaseHead: baseHead,
    );
    expect(v.isValid, isTrue);
  });

  test('G009-E1b alias candidatePatchSha256 aceita', () {
    final path = path_lib.join(tempDir.path, 'ev-e1b.json');
    final json = baseEvidence();
    json.remove('functionalPatchSha256');
    json['candidatePatchSha256'] = functionalSha;
    File(path).writeAsStringSync(jsonEncode(json));
    final v = GuardianEvidenceValidator.validate(
      repoRoot: repoRoot,
      evidencePath: path,
      expectedPatchSha256: functionalSha,
    );
    expect(v.isValid, isTrue);
  });

  const zero64 = '0000000000000000000000000000000000000000000000000000000000000000';
  const one64 = '1111111111111111111111111111111111111111111111111111111111111111';

  test('G009-E2 rules hash diferente rejeita', () async {
    final path = await writeEvidence(baseEvidence(rulesHash: zero64));
    final v = GuardianEvidenceValidator.validate(
      repoRoot: repoRoot,
      evidencePath: path,
    );
    expect(v.isValid, isFalse);
    expect(v.rejectionReason, 'evidence_rules_hash_mismatch');
  });

  test('G009-E3 teste hash diferente rejeita', () async {
    final path = await writeEvidence(baseEvidence(emulatorHash: one64));
    final v = GuardianEvidenceValidator.validate(
      repoRoot: repoRoot,
      evidencePath: path,
    );
    expect(v.isValid, isFalse);
    expect(v.rejectionReason, contains('evidence_test_hash_mismatch'));
  });

  test('G009-E4 failed > 0 rejeita', () async {
    final path = await writeEvidence(baseEvidence(failed: 1));
    final v = GuardianEvidenceValidator.validate(
      repoRoot: repoRoot,
      evidencePath: path,
    );
    expect(v.isValid, isFalse);
    expect(v.rejectionReason, 'evidence_failed_gt_zero');
  });

  test('G009-E5 exit code não zero rejeita', () async {
    final path = await writeEvidence(baseEvidence(exitCode: 1));
    final v = GuardianEvidenceValidator.validate(
      repoRoot: repoRoot,
      evidencePath: path,
    );
    expect(v.isValid, isFalse);
    expect(v.rejectionReason, 'evidence_exit_code_nonzero');
  });

  test('G009-E6 JSON arbitrário não executa comandos', () async {
    final path = await writeEvidence({
      ...baseEvidence(),
      'command': 'rm -rf /',
    });
    final before = Directory(repoRoot).listSync().length;
    final v = GuardianEvidenceValidator.validate(
      repoRoot: repoRoot,
      evidencePath: path,
    );
    final after = Directory(repoRoot).listSync().length;
    expect(before, after);
    expect(v.isValid, isTrue);
  });

  test('G009-E7 base HEAD divergente rejeita', () async {
    final path = await writeEvidence(
      baseEvidence(evidenceBaseHead: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'),
    );
    final v = GuardianEvidenceValidator.validate(
      repoRoot: repoRoot,
      evidencePath: path,
      expectedBaseHead: baseHead,
    );
    expect(v.isValid, isFalse);
    expect(v.rejectionReason, 'evidence_base_head_mismatch');
  });

  test('G009-E8 patch funcional divergente rejeita', () async {
    final path = await writeEvidence(
      baseEvidence(functionalPatchSha: one64),
    );
    final v = GuardianEvidenceValidator.validate(
      repoRoot: repoRoot,
      evidencePath: path,
      expectedFunctionalPatchSha256: functionalSha,
    );
    expect(v.isValid, isFalse);
    expect(v.rejectionReason, 'evidence_functional_patch_sha_mismatch');
  });
}
