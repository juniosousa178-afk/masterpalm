import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';

void main() {
  group('shouldPreserveLocalQuantidadeOnFirestorePull', () {
    test('mantém quantidade quando local updatedAt é posterior ao remoto', () {
      final local = DateTime(2026, 4, 17, 12, 0, 1);
      final remote = DateTime(2026, 4, 17, 12, 0, 0);
      expect(
        ProdutosFirestoreService.shouldPreserveLocalQuantidadeOnFirestorePull(
          localUpdatedAt: local,
          remoteUpdatedAt: remote,
        ),
        true,
      );
    });

    test('aplica remoto quando local é anterior ao remoto', () {
      final local = DateTime(2026, 4, 17, 11, 0, 0);
      final remote = DateTime(2026, 4, 17, 12, 0, 0);
      expect(
        ProdutosFirestoreService.shouldPreserveLocalQuantidadeOnFirestorePull(
          localUpdatedAt: local,
          remoteUpdatedAt: remote,
        ),
        false,
      );
    });

    test('sem updatedAt local não preserva (aplica política remota)', () {
      expect(
        ProdutosFirestoreService.shouldPreserveLocalQuantidadeOnFirestorePull(
          localUpdatedAt: null,
          remoteUpdatedAt: DateTime(2026, 1, 1),
        ),
        false,
      );
    });

    test('remoto sem updatedAt: preserva se local tem marca de recência', () {
      expect(
        ProdutosFirestoreService.shouldPreserveLocalQuantidadeOnFirestorePull(
          localUpdatedAt: DateTime(2026, 4, 17),
          remoteUpdatedAt: null,
        ),
        true,
      );
    });

    test('caso normal sem conflito: remoto mais novo que local', () {
      expect(
        ProdutosFirestoreService.shouldPreserveLocalQuantidadeOnFirestorePull(
          localUpdatedAt: DateTime(2026, 4, 1),
          remoteUpdatedAt: DateTime(2026, 4, 17),
        ),
        false,
      );
    });
  });
}
