import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Contrato fail-closed para evidência G009 (emulator rules).
class GuardianEvidenceDocument {
  GuardianEvidenceDocument({
    required this.schemaVersion,
    required this.baseHead,
    required this.functionalPatchSha256,
    this.guardianPatchSha256,
    this.candidatePatchSha256,
    required this.command,
    required this.workingDirectory,
    required this.firestoreRulesSha256,
    required this.testFiles,
    required this.passed,
    required this.failed,
    required this.skipped,
    required this.exitCode,
  });

  final int schemaVersion;
  final String baseHead;
  final String functionalPatchSha256;
  final String? guardianPatchSha256;
  final String? candidatePatchSha256;
  final String command;
  final String workingDirectory;
  final String firestoreRulesSha256;
  final List<GuardianEvidenceTestFile> testFiles;
  final int passed;
  final int failed;
  final int skipped;
  final int exitCode;

  static GuardianEvidenceDocument? tryParse(Map<String, dynamic> json) {
    try {
      final rawTests = json['testFiles'];
      if (rawTests is! List) return null;
      final tests = <GuardianEvidenceTestFile>[];
      for (final item in rawTests) {
        if (item is! Map) return null;
        final path = item['path'];
        final sha = item['sha256'];
        if (path is! String || sha is! String) return null;
        tests.add(
            GuardianEvidenceTestFile(path: path, sha256: sha.toLowerCase()));
      }

      final functional = json['functionalPatchSha256'] as String? ??
          json['candidatePatchSha256'] as String?;
      if (functional == null) return null;

      return GuardianEvidenceDocument(
        schemaVersion: json['schemaVersion'] as int,
        baseHead: json['baseHead'] as String,
        functionalPatchSha256: functional.toLowerCase(),
        guardianPatchSha256: (json['guardianPatchSha256'] as String?)
            ?.toLowerCase(),
        candidatePatchSha256: (json['candidatePatchSha256'] as String?)
            ?.toLowerCase(),
        command: json['command'] as String,
        workingDirectory: json['workingDirectory'] as String,
        firestoreRulesSha256:
            (json['firestoreRulesSha256'] as String).toLowerCase(),
        testFiles: tests,
        passed: json['passed'] as int,
        failed: json['failed'] as int,
        skipped: json['skipped'] as int,
        exitCode: json['exitCode'] as int,
      );
    } catch (_) {
      return null;
    }
  }
}

class GuardianEvidenceTestFile {
  GuardianEvidenceTestFile({required this.path, required this.sha256});

  final String path;
  final String sha256;
}

class GuardianEvidenceValidation {
  GuardianEvidenceValidation.valid()
      : isValid = true,
        rejectionReason = null;

  GuardianEvidenceValidation.rejected(this.rejectionReason) : isValid = false;

  final bool isValid;
  final String? rejectionReason;
}

class GuardianEvidenceValidator {
  /// Valida JSON de evidência contra o repo. Nunca executa [command].
  static GuardianEvidenceValidation validate({
    required String repoRoot,
    required String evidencePath,
    String? expectedFunctionalPatchSha256,
    String? expectedPatchSha256,
    String? expectedBaseHead,
  }) {
    final expectedFunctional = (expectedFunctionalPatchSha256 ??
            expectedPatchSha256)
        ?.toLowerCase();

    final file = File(evidencePath);
    if (!file.existsSync()) {
      return GuardianEvidenceValidation.rejected('evidence_file_missing');
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return GuardianEvidenceValidation.rejected('evidence_json_invalid');
    }

    final doc = GuardianEvidenceDocument.tryParse(json);
    if (doc == null) {
      return GuardianEvidenceValidation.rejected('evidence_schema_invalid');
    }

    if (doc.schemaVersion != 1) {
      return GuardianEvidenceValidation.rejected('evidence_schema_unknown');
    }

    if (expectedBaseHead != null &&
        expectedBaseHead.isNotEmpty &&
        doc.baseHead.trim() != expectedBaseHead.trim()) {
      return GuardianEvidenceValidation.rejected('evidence_base_head_mismatch');
    }

    if (expectedFunctional != null &&
        expectedFunctional.isNotEmpty &&
        doc.functionalPatchSha256 != expectedFunctional) {
      return GuardianEvidenceValidation.rejected(
          'evidence_functional_patch_sha_mismatch');
    }

    if (doc.exitCode != 0) {
      return GuardianEvidenceValidation.rejected('evidence_exit_code_nonzero');
    }

    if (doc.failed > 0) {
      return GuardianEvidenceValidation.rejected('evidence_failed_gt_zero');
    }

    final rulesPath = p.join(repoRoot, 'firestore.rules');
    if (!File(rulesPath).existsSync()) {
      return GuardianEvidenceValidation.rejected('firestore_rules_missing');
    }
    final rulesHash = _sha256File(rulesPath).toLowerCase();
    if (rulesHash != doc.firestoreRulesSha256) {
      return GuardianEvidenceValidation.rejected('evidence_rules_hash_mismatch');
    }

    for (final tf in doc.testFiles) {
      final rel = tf.path.replaceAll('\\', '/');
      final full = p.join(repoRoot, rel);
      if (!File(full).existsSync()) {
        return GuardianEvidenceValidation.rejected(
            'evidence_test_file_missing:$rel');
      }
      final hash = _sha256File(full).toLowerCase();
      if (hash != tf.sha256) {
        return GuardianEvidenceValidation.rejected(
            'evidence_test_hash_mismatch:$rel');
      }
    }

    return GuardianEvidenceValidation.valid();
  }

  static String _sha256File(String path) {
    final bytes = File(path).readAsBytesSync();
    return sha256.convert(bytes).toString();
  }
}
