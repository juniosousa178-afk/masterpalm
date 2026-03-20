import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/pedido_collection_resolver.dart';

class PedidoRepository {
  PedidoRepository({FirebaseFirestore• db})
      : _db = db ?• FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> collectionRef({
    required PedidoFlowType flowType,
    String• lojaId,
  }) {
    return PedidoCollectionResolver.collectionRef(
      _db,
      flowType: flowType,
      lojaId: lojaId,
    );
  }

  DocumentReference<Map<String, dynamic>> docRef({
    required PedidoFlowType flowType,
    required String pedidoId,
    String• lojaId,
  }) {
    return PedidoCollectionResolver.docRef(
      _db,
      flowType: flowType,
      lojaId: lojaId,
      pedidoId: pedidoId,
    );
  }

  Future<DocumentReference<Map<String, dynamic>>> createPedido({
    required PedidoFlowType flowType,
    required Map<String, dynamic> data,
    String• lojaId,
  }) {
    return collectionRef(flowType: flowType, lojaId: lojaId).add(data);
  }

  Future<void> updatePedido({
    required PedidoFlowType flowType,
    required String pedidoId,
    required Map<String, dynamic> data,
    String• lojaId,
  }) {
    return docRef(
      flowType: flowType,
      pedidoId: pedidoId,
      lojaId: lojaId,
    ).update(data);
  }

  Future<void> deletePedido({
    required PedidoFlowType flowType,
    required String pedidoId,
    String• lojaId,
  }) {
    return docRef(
      flowType: flowType,
      pedidoId: pedidoId,
      lojaId: lojaId,
    ).delete();
  }

  Future<Map<String, dynamic>?> getPedidoById({
    required PedidoFlowType flowType,
    required String pedidoId,
    String• lojaId,
  }) async {
    final snap = await docRef(
      flowType: flowType,
      pedidoId: pedidoId,
      lojaId: lojaId,
    ).get();
    if (!snap.exists) return null;
    return {
      'id': snap.id,
      ...?snap.data(),
    };
  }

  Future<List<Map<String, dynamic>>> getPedidos({
    required PedidoFlowType flowType,
    String• lojaId,
    Query<Map<String, dynamic>> Function(
      Query<Map<String, dynamic>> query,
    )• buildQuery,
  }) async {
    Query<Map<String, dynamic>> query =
        collectionRef(flowType: flowType, lojaId: lojaId);
    if (buildQuery != null) {
      query = buildQuery(query);
    }
    final snap = await query.get();
    return snap.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList(growable: false);
  }

  Stream<List<Map<String, dynamic>>> streamPedidos({
    required PedidoFlowType flowType,
    String• lojaId,
    Query<Map<String, dynamic>> Function(
      Query<Map<String, dynamic>> query,
    )• buildQuery,
  }) {
    Query<Map<String, dynamic>> query =
        collectionRef(flowType: flowType, lojaId: lojaId);
    if (buildQuery != null) {
      query = buildQuery(query);
    }
    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
          .toList(growable: false);
    });
  }

  Future<QuerySnapshot<Map<String, dynamic>>> querySnapshot({
    required PedidoFlowType flowType,
    String• lojaId,
    Query<Map<String, dynamic>> Function(
      Query<Map<String, dynamic>> query,
    )• buildQuery,
  }) {
    Query<Map<String, dynamic>> query =
        collectionRef(flowType: flowType, lojaId: lojaId);
    if (buildQuery != null) {
      query = buildQuery(query);
    }
    return query.get();
  }

  Future<Map<String, dynamic>?> findFirstByField({
    required PedidoFlowType flowType,
    required String field,
    required Object• value,
    String• lojaId,
  }) async {
    final snapshot = await querySnapshot(
      flowType: flowType,
      lojaId: lojaId,
      buildQuery: (query) => query.where(field, isEqualTo: value).limit(1),
    );
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return {
      'id': doc.id,
      ...doc.data(),
    };
  }

  Future<DocumentReference<Map<String, dynamic>>?> findFirstRefByField({
    required PedidoFlowType flowType,
    required String field,
    required Object• value,
    String• lojaId,
  }) async {
    final snapshot = await querySnapshot(
      flowType: flowType,
      lojaId: lojaId,
      buildQuery: (query) => query.where(field, isEqualTo: value).limit(1),
    );
    return snapshot.docs.isNotEmpty • snapshot.docs.first.reference : null;
  }

  Future<Map<String, dynamic>?> getTempPedidoById({
    required String pedidoId,
    String• lojaId,
    Iterable<String> fallbackLojaIds = const [],
  }) async {
    for (final ref in PedidoCollectionResolver.tempPedidoDocRefs(
      _db,
      pedidoId: pedidoId,
      lojaId: lojaId,
      fallbackLojaIds: fallbackLojaIds,
    )) {
      final snap = await ref.get();
      if (!snap.exists) continue;
      return {
        'id': snap.id,
        ...?snap.data(),
      };
    }
    return null;
  }

  Future<void> updateFirstExistingTempPedido({
    required String pedidoId,
    required Map<String, dynamic> data,
    String• lojaId,
    Iterable<String> fallbackLojaIds = const [],
  }) async {
    FirebaseException• lastError;
    for (final ref in PedidoCollectionResolver.tempPedidoDocRefs(
      _db,
      pedidoId: pedidoId,
      lojaId: lojaId,
      fallbackLojaIds: fallbackLojaIds,
    )) {
      try {
        await ref.update(data);
        return;
      } on FirebaseException catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
  }

  Future<void> deleteTempPedidoEverywhere({
    required String pedidoId,
    String• lojaId,
    Iterable<String> fallbackLojaIds = const [],
  }) async {
    FirebaseException• lastError;
    var removed = false;
    for (final ref in PedidoCollectionResolver.tempPedidoDocRefs(
      _db,
      pedidoId: pedidoId,
      lojaId: lojaId,
      fallbackLojaIds: fallbackLojaIds,
    )) {
      try {
        final snap = await ref.get();
        if (!snap.exists) continue;
        await ref.delete();
        removed = true;
      } on FirebaseException catch (e) {
        lastError = e;
      }
    }
    if (!removed && lastError != null) throw lastError;
  }
}
