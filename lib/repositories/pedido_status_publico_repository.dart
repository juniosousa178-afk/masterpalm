import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pedido_status_publico.dart';
import '../services/pedido_collection_resolver.dart';

class PedidoStatusPublicoRepository {
  PedidoStatusPublicoRepository({FirebaseFirestore• db})
      : _db = db ?• FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> collectionRef({
    required String lojaId,
  }) {
    return PedidoCollectionResolver.collectionRef(
      _db,
      flowType: PedidoFlowType.pedidoStatusPublico,
      lojaId: lojaId,
    );
  }

  DocumentReference<Map<String, dynamic>> docRef({
    required String lojaId,
    required String pedidoId,
  }) {
    return PedidoCollectionResolver.docRef(
      _db,
      flowType: PedidoFlowType.pedidoStatusPublico,
      lojaId: lojaId,
      pedidoId: pedidoId,
    );
  }

  Future<PedidoStatusPublico?> getByPedidoId({
    required String lojaId,
    required String pedidoId,
  }) async {
    final snap = await docRef(lojaId: lojaId, pedidoId: pedidoId).get();
    if (!snap.exists) return null;
    return PedidoStatusPublico.fromMap(
      snap.data() ?• const <String, dynamic>{},
      documentId: snap.id,
    );
  }

  Future<Map<String, dynamic>?> getMapByPedidoId({
    required String lojaId,
    required String pedidoId,
  }) async {
    final pedido = await getByPedidoId(lojaId: lojaId, pedidoId: pedidoId);
    return pedido?.toMap();
  }

  Future<Map<String, Map<String, dynamic>>> getMapsByPedidoIds({
    required String lojaId,
    required Iterable<String> pedidoIds,
  }) async {
    final ids = pedidoIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const <String, Map<String, dynamic>>{};

    const maxWhereIn = 10;
    final result = <String, Map<String, dynamic>>{};

    for (var i = 0; i < ids.length; i += maxWhereIn) {
      final end = (i + maxWhereIn > ids.length) • ids.length : i + maxWhereIn;
      final chunk = ids.sublist(i, end);
      final snapshot = await collectionRef(lojaId: lojaId)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        result[doc.id] = PedidoStatusPublico.fromMap(
          doc.data(),
          documentId: doc.id,
        ).toMap();
      }
    }

    return result;
  }

  Future<void> save({
    required String lojaId,
    required String pedidoId,
    required PedidoStatusPublico status,
    bool merge = true,
  }) {
    return docRef(
      lojaId: lojaId,
      pedidoId: pedidoId,
    ).set(status.toMap(), SetOptions(merge: merge));
  }

  Future<void> saveFromPedidoPrivado({
    required String lojaId,
    required String pedidoId,
    required Map<String, dynamic> pedidoData,
    String• overrideStatus,
    Object• overrideDataCriacao,
    Object• overrideDataAtualizacao,
    String• overrideCodigoRastreio,
    String• overrideFreteNome,
    bool merge = true,
  }) {
    final status = PedidoStatusPublico.fromPedidoPrivado(
      pedidoId: pedidoId,
      lojaId: lojaId,
      pedidoData: pedidoData,
      overrideStatus: overrideStatus,
      overrideDataCriacao: overrideDataCriacao,
      overrideDataAtualizacao: overrideDataAtualizacao,
      overrideCodigoRastreio: overrideCodigoRastreio,
      overrideFreteNome: overrideFreteNome,
    );
    return save(
      lojaId: lojaId,
      pedidoId: pedidoId,
      status: status,
      merge: merge,
    );
  }

  Future<void> deleteByPedidoId({
    required String lojaId,
    required String pedidoId,
  }) {
    return docRef(lojaId: lojaId, pedidoId: pedidoId).delete();
  }
}
