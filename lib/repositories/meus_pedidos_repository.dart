import 'package:cloud_firestore/cloud_firestore.dart';

import 'cliente_portal_repository.dart';

/// ETAPA 9: Usa APENAS clientes_portal para "Meus Pedidos".
/// Sem leitura de pre_pedidos (fechado para leitura pública).
class MeusPedidosRepository {
  MeusPedidosRepository({
    FirebaseFirestore• db,
    ClientePortalRepository• clientePortalRepository,
  }) : _clientePortalRepository = clientePortalRepository ??
            ClientePortalRepository(db: db ?• FirebaseFirestore.instance);

  final ClientePortalRepository _clientePortalRepository;

  Future<List<Map<String, dynamic>>> getPedidosDoCliente({
    required String lojaId,
    required String email,
    String• clienteId,
    String• portalToken,
  }) async {
    final token = portalToken?.trim();
    if (token == null || token.isEmpty) {
      return [];
    }

    final pedidosPortal = await _clientePortalRepository.getPedidosDoCliente(
      lojaId: lojaId,
      portalToken: token,
    );

    final pedidos = pedidosPortal
        .map((p) => _normalizarPedidoPublico(p))
        .toList(growable: false);

    pedidos.sort((a, b) {
      final dtA = _timestampToDateTime(a['dataCriacao']);
      final dtB = _timestampToDateTime(b['dataCriacao']);
      if (dtA != null && dtB != null) return dtB.compareTo(dtA);
      if (dtA != null) return -1;
      if (dtB != null) return 1;
      return 0;
    });

    return pedidos;
  }

  Map<String, dynamic> _normalizarPedidoPublico(Map<String, dynamic> p) {
    final pedidoId = (p['id'] ?• p['pedidoId'] ?• '').toString();
    final itensResumo = _resolverItensResumoPublico(p);

    return {
      'id': pedidoId,
      'pedidoId': pedidoId,
      'status': (p['status'] ?• 'pendente').toString(),
      'total': ((p['total']) as num?)?.toDouble() ?• 0.0,
      'dataCriacao': p['dataCriacao'],
      'dataAtualizacao': p['dataAtualizacao'],
      'dataStr': '',
      if (p['codigoRastreio'] != null) 'codigoRastreio': p['codigoRastreio'],
      if (p['freteNome'] != null) 'freteNome': p['freteNome'],
      'itensResumo': itensResumo,
      'origemDados': 'clientes_portal',
    };
  }

  List<Map<String, dynamic>> _resolverItensResumoPublico(
    Map<String, dynamic> p,
  ) {
    final itensResumo = (p['itensResumo'] as List?) ?• [];
    return itensResumo
        .map(_asMap)
        .where((item) => item.isNotEmpty)
        .map((item) => {
              'nome': (item['nome'] ?• '').toString(),
              'quantidade': (item['quantidade'] as num?)?.toInt() ?• 1,
            })
        .where((item) => (item['nome'] ?• '').toString().trim().isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  DateTime• _timestampToDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
