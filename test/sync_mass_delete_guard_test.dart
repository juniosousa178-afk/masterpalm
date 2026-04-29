import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/sync_mass_delete_guard.dart';

void main() {
  group('SyncMassDeleteGuard catálogo', () {
    test('allowed vazio e remote > 0 bloqueia', () {
      expect(
        SyncMassDeleteGuard.catalogBlockReason(
          allowedCount: 0,
          remoteCount: 5,
          deleteCandidatesCount: 5,
          allowMassDelete: false,
        ),
        SyncMassDeleteBlockReason.allowedEmptyWithRemote,
      );
    });

    test('allowed vazio e remote > 0 não bloqueia com allowMassDelete', () {
      expect(
        SyncMassDeleteGuard.catalogBlockReason(
          allowedCount: 0,
          remoteCount: 5,
          deleteCandidatesCount: 5,
          allowMassDelete: true,
        ),
        SyncMassDeleteBlockReason.none,
      );
    });

    test('muitos candidatos a delete bloqueia', () {
      expect(
        SyncMassDeleteGuard.catalogBlockReason(
          allowedCount: 100,
          remoteCount: 100,
          deleteCandidatesCount: 21,
          allowMassDelete: false,
        ),
        SyncMassDeleteBlockReason.deleteCountOverAbsoluteCap,
      );
    });

    test('fração alta de delete bloqueia', () {
      expect(
        SyncMassDeleteGuard.catalogBlockReason(
          allowedCount: 50,
          remoteCount: 10,
          deleteCandidatesCount: 4,
          allowMassDelete: false,
        ),
        SyncMassDeleteBlockReason.deleteFractionOverCap,
      );
    });

    test('delete pequeno e seguro não bloqueia', () {
      expect(
        SyncMassDeleteGuard.catalogBlockReason(
          allowedCount: 10,
          remoteCount: 100,
          deleteCandidatesCount: 5,
          allowMassDelete: false,
        ),
        SyncMassDeleteBlockReason.none,
      );
    });
  });

  group('SyncMassDeleteGuard estoque excedentes', () {
    test('localIds vazio e remote > 0 bloqueia', () {
      expect(
        SyncMassDeleteGuard.estoqueExcedentesBlockReason(
          localIdsCount: 0,
          remoteCount: 3,
          deleteCandidatesCount: 3,
          allowMassDelete: false,
        ),
        SyncMassDeleteBlockReason.localIdsEmptyWithRemote,
      );
    });

    test('localIds vazio e remote 0 não bloqueia', () {
      expect(
        SyncMassDeleteGuard.estoqueExcedentesBlockReason(
          localIdsCount: 0,
          remoteCount: 0,
          deleteCandidatesCount: 0,
          allowMassDelete: false,
        ),
        SyncMassDeleteBlockReason.none,
      );
    });

    test('muitos candidatos a delete bloqueia', () {
      expect(
        SyncMassDeleteGuard.estoqueExcedentesBlockReason(
          localIdsCount: 50,
          remoteCount: 50,
          deleteCandidatesCount: 25,
          allowMassDelete: false,
        ),
        SyncMassDeleteBlockReason.deleteCountOverAbsoluteCap,
      );
    });

    test('fração alta bloqueia', () {
      expect(
        SyncMassDeleteGuard.estoqueExcedentesBlockReason(
          localIdsCount: 5,
          remoteCount: 20,
          deleteCandidatesCount: 7,
          allowMassDelete: false,
        ),
        SyncMassDeleteBlockReason.deleteFractionOverCap,
      );
    });
  });
}
