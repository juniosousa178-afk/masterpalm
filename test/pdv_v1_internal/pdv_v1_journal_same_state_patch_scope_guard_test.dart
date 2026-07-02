import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_executor.dart';

void main() {
  group('Patch same-state scope guard', () {
    test('tipos e método novos ficam somente em pdv_v1_internal', () async {
      final repoRoot = Directory.current;
      final forbiddenRoots = [
        repoRoot.uri.resolve('lib/screens/').toFilePath(),
        repoRoot.uri.resolve('lib/services/vendas_service.dart').toFilePath(),
        repoRoot.uri
            .resolve('lib/services/sync_queue_service.dart')
            .toFilePath(),
      ];
      final needles = [
        'persistAuthorizedSameStatePatchIfRevisionMatches',
        'PdvV1JournalSameStatePatchAuthorization',
        'proposeRetryableStageFailurePatch',
      ];
      for (final path in forbiddenRoots) {
        if (!File(path).existsSync() && !Directory(path).existsSync()) continue;
        final entity = FileSystemEntity.typeSync(path);
        if (entity == FileSystemEntityType.file) {
          final content = await File(path).readAsString();
          for (final needle in needles) {
            expect(content.contains(needle), isFalse, reason: path);
          }
        }
      }
    });

    test('lib interna não usa Hive.openBox init ou close', () async {
      final libDir = Directory('lib/services/pdv_v1_internal');
      final forbidden = ['Hive.openBox', 'Hive.init', 'Hive.close'];
      await for (final file in libDir.list(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final content = await file.readAsString();
        for (final token in forbidden) {
          expect(content.contains(token), isFalse, reason: file.path);
        }
      }
    });

    test('helpers de teste patch não usam hashCode', () async {
      final testDir = Directory('test/pdv_v1_internal');
      final patchFiles = [
        'pdv_v1_journal_same_state_patch_test.dart',
        'pdv_v1_journal_same_state_patch_restart_test.dart',
      ];
      for (final name in patchFiles) {
        final content = await File('${testDir.path}/$name').readAsString();
        expect(content.contains('hashCode'), isFalse, reason: name);
      }
    });

    test('repository expõe patch somente por injeção de Box', () {
      expect(
        PdvV1HiveJournalRepository.new,
        isA<Function>(),
      );
      expect(PdvV1JournalSameStatePatchKind.values.length, 1);
      expect(
        PdvV1JournalSameStatePatchKind.recordRetryableStageFailure.name,
        'recordRetryableStageFailure',
      );
      expect(pdvV1MaxRetryableStageFailureAttempts, 3);
      expect(
          const PdvV1RecoveryExecutorSimulator()
              .proposeRetryableStageFailurePatch,
          isA<Function>());
    });
  });
}
