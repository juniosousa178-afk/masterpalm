// Observador de failpoint para testes de atomicidade da recuperação.

import 'package:master_palm/services/produto_sync_recovery_models.dart';

class RecoveryFailpointObserver implements RecoveryExecutionObserver {
  RecoveryFailpointObserver(this.failAfter);

  final RecoveryExecutionCheckpoint failAfter;

  @override
  Future<void> onCheckpoint(
    RecoveryExecutionCheckpoint checkpoint,
    RecoveryJournalEntry entry,
  ) async {
    if (checkpoint == failAfter) {
      throw StateError('failpoint:$checkpoint');
    }
  }
}
