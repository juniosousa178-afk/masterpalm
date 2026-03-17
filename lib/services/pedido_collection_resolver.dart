import 'package:cloud_firestore/cloud_firestore.dart';

enum PedidoFlowType {
  pedidos,
  prePedidos,
  pedidoStatusPublico,
  pedidosPendentes,
  pedidosTemp,
  pedidoTempLegado,
  pedidosCatalogo,
  tempOrders,
  rootPedidos,
  rootPedidosTemp,
}

/// Centraliza os caminhos Firestore relacionados aos diferentes fluxos de pedido.
///
/// Importante:
/// - Não migra dados.
/// - Não troca a coleção real usada por cada fluxo.
/// - Apenas evita strings espalhadas e reduz inconsistências.
class PedidoCollectionResolver {
  PedidoCollectionResolver._();

  static const String lojasCollection = 'lojas';
  static const String pedidosCollection = 'pedidos';
  static const String prePedidosCollection = 'pre_pedidos';
  static const String pedidoStatusPublicoCollection = 'pedido_status_publico';
  static const String pedidosPendentesCollection = 'pedidos_pendentes';
  static const String pedidosTempCollection = 'pedidos_temp';
  static const String pedidoTempLegadoCollection = 'pedido_temp';
  static const String pedidosCatalogoCollection = 'pedidos_catalogo';
  static const String tempOrdersCollection = 'temp_orders';

  static bool isRootFlow(PedidoFlowType flowType) {
    return flowType == PedidoFlowType.rootPedidos ||
        flowType == PedidoFlowType.rootPedidosTemp;
  }

  static String collectionName(PedidoFlowType flowType) {
    switch (flowType) {
      case PedidoFlowType.pedidos:
      case PedidoFlowType.rootPedidos:
        return pedidosCollection;
      case PedidoFlowType.prePedidos:
        return prePedidosCollection;
      case PedidoFlowType.pedidoStatusPublico:
        return pedidoStatusPublicoCollection;
      case PedidoFlowType.pedidosPendentes:
        return pedidosPendentesCollection;
      case PedidoFlowType.pedidosTemp:
      case PedidoFlowType.rootPedidosTemp:
        return pedidosTempCollection;
      case PedidoFlowType.pedidoTempLegado:
        return pedidoTempLegadoCollection;
      case PedidoFlowType.pedidosCatalogo:
        return pedidosCatalogoCollection;
      case PedidoFlowType.tempOrders:
        return tempOrdersCollection;
    }
  }

  static String collectionPath({
    required PedidoFlowType flowType,
    String? lojaId,
  }) {
    final collection = collectionName(flowType);
    if (isRootFlow(flowType)) return collection;
    final resolvedLojaId = _requireLojaId(lojaId, flowType);
    return '$lojasCollection/$resolvedLojaId/$collection';
  }

  static String docPath({
    required PedidoFlowType flowType,
    required String pedidoId,
    String? lojaId,
  }) {
    return '${collectionPath(flowType: flowType, lojaId: lojaId)}/$pedidoId';
  }

  static CollectionReference<Map<String, dynamic>> collectionRef(
    FirebaseFirestore db, {
    required PedidoFlowType flowType,
    String? lojaId,
  }) {
    if (isRootFlow(flowType)) {
      return db.collection(collectionName(flowType));
    }
    final resolvedLojaId = _requireLojaId(lojaId, flowType);
    return db
        .collection(lojasCollection)
        .doc(resolvedLojaId)
        .collection(collectionName(flowType));
  }

  static DocumentReference<Map<String, dynamic>> docRef(
    FirebaseFirestore db, {
    required PedidoFlowType flowType,
    required String pedidoId,
    String? lojaId,
  }) {
    return collectionRef(db, flowType: flowType, lojaId: lojaId).doc(pedidoId);
  }

  static List<DocumentReference<Map<String, dynamic>>> tempPedidoDocRefs(
    FirebaseFirestore db, {
    required String pedidoId,
    String? lojaId,
    Iterable<String> fallbackLojaIds = const [],
    bool includeRoot = true,
    bool includeLegacy = true,
  }) {
    final refs = <DocumentReference<Map<String, dynamic>>>[];
    final ids = <String>{
      if (lojaId != null && lojaId.trim().isNotEmpty) lojaId.trim(),
      ...fallbackLojaIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
    };

    for (final id in ids) {
      refs.add(docRef(
        db,
        flowType: PedidoFlowType.pedidosTemp,
        lojaId: id,
        pedidoId: pedidoId,
      ));
      if (includeLegacy) {
        refs.add(docRef(
          db,
          flowType: PedidoFlowType.pedidoTempLegado,
          lojaId: id,
          pedidoId: pedidoId,
        ));
        refs.add(docRef(
          db,
          flowType: PedidoFlowType.tempOrders,
          lojaId: id,
          pedidoId: pedidoId,
        ));
      }
    }

    if (includeRoot) {
      refs.add(docRef(
        db,
        flowType: PedidoFlowType.rootPedidosTemp,
        pedidoId: pedidoId,
      ));
    }

    return refs;
  }

  static String _requireLojaId(String? lojaId, PedidoFlowType flowType) {
    final resolved = lojaId?.trim();
    if (resolved == null || resolved.isEmpty) {
      throw ArgumentError(
        'lojaId é obrigatório para o fluxo ${flowType.name}',
      );
    }
    return resolved;
  }
}
