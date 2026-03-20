class PedidoStatusPublicoItemResumo {
  const PedidoStatusPublicoItemResumo({
    required this.nome,
    required this.quantidade,
  });

  final String nome;
  final int quantidade;

  factory PedidoStatusPublicoItemResumo.fromMap(Map<String, dynamic> map) {
    return PedidoStatusPublicoItemResumo(
      nome: (map['nome'] ?? '').toString(),
      quantidade: (map['quantidade'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'quantidade': quantidade,
    };
  }
}

class PedidoStatusPublico {
  const PedidoStatusPublico({
    required this.pedidoId,
    required this.lojaId,
    required this.status,
    required this.dataCriacao,
    required this.dataAtualizacao,
    required this.total,
    required this.itensResumo,
    this.codigoRastreio,
    this.freteNome,
  });

  final String pedidoId;
  final String lojaId;
  final String status;
  final Object? dataCriacao;
  final Object? dataAtualizacao;
  final double total;
  final List<PedidoStatusPublicoItemResumo> itensResumo;
  final String? codigoRastreio;
  final String? freteNome;

  factory PedidoStatusPublico.fromMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    final rawItens = (map['itensResumo'] as List?) ?? const [];
    return PedidoStatusPublico(
      pedidoId: (map['pedidoId'] ?? documentId ?? '').toString(),
      lojaId: (map['lojaId'] ?? '').toString(),
      status: (map['status'] ?? 'pendente').toString(),
      dataCriacao: map['dataCriacao'],
      dataAtualizacao: map['dataAtualizacao'],
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      itensResumo: rawItens
          .whereType<Map>()
          .map((item) => PedidoStatusPublicoItemResumo.fromMap(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false),
      codigoRastreio: _stringOrNull(map['codigoRastreio']),
      freteNome: _stringOrNull(map['freteNome']),
    );
  }

  factory PedidoStatusPublico.fromPedidoPrivado({
    required String pedidoId,
    required String lojaId,
    required Map<String, dynamic> pedidoData,
    String? overrideStatus,
    Object? overrideDataCriacao,
    Object? overrideDataAtualizacao,
    String? overrideCodigoRastreio,
    String? overrideFreteNome,
  }) {
    final itens = (pedidoData['itens'] as List?) ?? const [];
    final itensResumo = itens
        .whereType<Map>()
        .map((item) {
          final itemMap = Map<String, dynamic>.from(item);
          return PedidoStatusPublicoItemResumo(
            nome: (itemMap['nome'] ?? '').toString(),
            quantidade: (itemMap['quantidade'] as num?)?.toInt() ?? 1,
          );
        })
        .where((item) => item.nome.trim().isNotEmpty)
        .toList(growable: false);

    final frete = pedidoData['frete'];
    final freteMap = frete is Map ? Map<String, dynamic>.from(frete) : null;

    return PedidoStatusPublico(
      pedidoId: pedidoId,
      lojaId: lojaId,
      status: (overrideStatus ?? pedidoData['status'] ?? 'pendente').toString(),
      dataCriacao: overrideDataCriacao ?? pedidoData['dataCriacao'],
      dataAtualizacao: overrideDataAtualizacao ?? pedidoData['dataAtualizacao'],
      total: (pedidoData['total'] as num?)?.toDouble() ?? 0.0,
      itensResumo: itensResumo,
      codigoRastreio: _stringOrNull(
        overrideCodigoRastreio ??
            pedidoData['codigoRastreio'] ??
            pedidoData['codigo_rastreio'] ??
            pedidoData['rastreio'],
      ),
      freteNome:
          _stringOrNull(overrideFreteNome ?? freteMap?['nome'] ?? pedidoData['freteNome']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'pedidoId': pedidoId,
      'lojaId': lojaId,
      'status': status,
      'dataCriacao': dataCriacao,
      'dataAtualizacao': dataAtualizacao,
      'total': total,
      'itensResumo': itensResumo.map((item) => item.toMap()).toList(),
      if (codigoRastreio != null) 'codigoRastreio': codigoRastreio,
      if (freteNome != null) 'freteNome': freteNome,
    };
  }

  static String? _stringOrNull(Object? value) {
    final resolved = value?.toString().trim();
    if (resolved == null || resolved.isEmpty) return null;
    return resolved;
  }
}
