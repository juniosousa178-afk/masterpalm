// Fixture de tombstone via FakeFirestore — somente testes.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';

/// Registra tombstone remoto simulado e hidrata cache local.
Future<void> registrarTombstoneRemotoFake({
  required FakeFirebaseFirestore firestore,
  required String lojaId,
  required String estoqueDocId,
}) async {
  ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;
  await firestore
      .collection('lojas')
      .doc(lojaId)
      .collection(FSPaths.exclusaoProdutoCol)
      .doc(estoqueDocId)
      .set({'p': true});
  ProdutoExclusaoTombstoneService.resetCacheForTests();
  await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);
}

void limparTombstoneFake() {
  ProdutoExclusaoTombstoneService.resetCacheForTests();
}
