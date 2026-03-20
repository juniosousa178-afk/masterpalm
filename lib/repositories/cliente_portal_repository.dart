import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_paths.dart';

class ClientePortalRepository {
  ClientePortalRepository({FirebaseFirestore• db})
      : _db = db ?• FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> profileRef({
    required String lojaId,
    required String portalToken,
  }) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.clientesPortalCol)
        .doc(portalToken);
  }

  CollectionReference<Map<String, dynamic>> pedidosRef({
    required String lojaId,
    required String portalToken,
  }) {
    return profileRef(lojaId: lojaId, portalToken: portalToken)
        .collection('pedidos');
  }

  Future<Map<String, dynamic>?> getPerfil({
    required String lojaId,
    required String portalToken,
  }) async {
    final snap = await profileRef(
      lojaId: lojaId,
      portalToken: portalToken,
    ).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  Future<Map<String, dynamic>?> getUltimoEndereco({
    required String lojaId,
    required String portalToken,
  }) async {
    final perfil = await getPerfil(lojaId: lojaId, portalToken: portalToken);
    if (perfil == null) return null;
    final endereco = perfil['ultimoEndereco'];
    if (endereco is Map) {
      return Map<String, dynamic>.from(endereco);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getPedidosDoCliente({
    required String lojaId,
    required String portalToken,
    int limit = 50,
  }) async {
    final snapshot = await pedidosRef(
      lojaId: lojaId,
      portalToken: portalToken,
    )
        .orderBy('dataCriacao', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList(growable: false);
  }

  Future<void> savePedidoResumo({
    required String lojaId,
    required String portalToken,
    required String pedidoId,
    required Map<String, dynamic> data,
  }) {
    return pedidosRef(
      lojaId: lojaId,
      portalToken: portalToken,
    ).doc(pedidoId).set(data, SetOptions(merge: false));
  }

  Future<void> deletePedidoResumo({
    required String lojaId,
    required String portalToken,
    required String pedidoId,
  }) {
    return pedidosRef(
      lojaId: lojaId,
      portalToken: portalToken,
    ).doc(pedidoId).delete();
  }
}
