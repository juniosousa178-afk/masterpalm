import 'package:cloud_firestore/cloud_firestore.dart';

/// Status de moderação (catálogo público só exibe [aprovado]).
enum CatalogAvaliacaoStatus {
  pendente,
  aprovado,
  rejeitado;

  static CatalogAvaliacaoStatus fromFirestore(dynamic raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    switch (s) {
      case 'pendente':
        return CatalogAvaliacaoStatus.pendente;
      case 'rejeitado':
        return CatalogAvaliacaoStatus.rejeitado;
      case 'aprovado':
        return CatalogAvaliacaoStatus.aprovado;
      default:
        // Compat: docs antigos sem campo `status` eram públicos no catálogo.
        return CatalogAvaliacaoStatus.aprovado;
    }
  }

  String get firestoreValue {
    switch (this) {
      case CatalogAvaliacaoStatus.pendente:
        return 'pendente';
      case CatalogAvaliacaoStatus.aprovado:
        return 'aprovado';
      case CatalogAvaliacaoStatus.rejeitado:
        return 'rejeitado';
    }
  }
}

class CatalogAvaliacao {
  final String id;
  final String lojaId;
  final String? produtoId;
  final String nomeCliente;
  final String comentario;
  final int estrelas;
  /// Data exibida no card (mantém compat com campo `data` existente).
  final DateTime data;
  final List<String> fotos;
  final bool isMock;

  final CatalogAvaliacaoStatus status;
  final DateTime? criadoEm;
  final DateTime? aprovadoEm;
  /// Ex.: catalogo_web, mock, admin — livre para evolução.
  final String? origem;

  const CatalogAvaliacao({
    required this.id,
    required this.lojaId,
    this.produtoId,
    required this.nomeCliente,
    required this.comentario,
    required this.estrelas,
    required this.data,
    this.fotos = const [],
    this.isMock = false,
    this.status = CatalogAvaliacaoStatus.aprovado,
    this.criadoEm,
    this.aprovadoEm,
    this.origem,
  });

  /// Visível no catálogo público: aprovados (inclui legado) ou mocks de fallback.
  bool get visivelNoCatalogoPublico =>
      isMock || status == CatalogAvaliacaoStatus.aprovado;

  factory CatalogAvaliacao.fromFirestore(
    String id,
    Map<String, dynamic> map,
  ) {
    DateTime? parseTs(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    DateTime parseData(dynamic raw) {
      final t = parseTs(raw);
      if (t != null) return t;
      return DateTime.now();
    }

    final estrelasRaw = map['estrelas'];
    final estrelas = estrelasRaw is num
        ? estrelasRaw.toInt()
        : int.tryParse('$estrelasRaw') ?? 5;

    final fotosRaw = map['fotos'];
    final fotos = fotosRaw is List
        ? fotosRaw
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList()
        : <String>[];

    final dataVal = parseData(map['data']);
    final criado = parseTs(map['criadoEm']);
    final aprovado = parseTs(map['aprovadoEm']);
    final statusVal = CatalogAvaliacaoStatus.fromFirestore(map['status']);

    return CatalogAvaliacao(
      id: id,
      lojaId: (map['lojaId'] ?? '').toString().trim(),
      produtoId: (map['produtoId'] ?? '').toString().trim().isEmpty
          ? null
          : (map['produtoId'] ?? '').toString().trim(),
      nomeCliente: (map['nomeCliente'] ?? '').toString().trim(),
      comentario: (map['comentario'] ?? '').toString().trim(),
      estrelas: estrelas.clamp(1, 5),
      data: dataVal,
      fotos: fotos,
      isMock: map['isMock'] == true,
      status: statusVal,
      criadoEm: criado,
      aprovadoEm: aprovado,
      origem: map['origem']?.toString(),
    );
  }

  /// Persistência de envio pelo catálogo (novo = pendente).
  Map<String, dynamic> toFirestoreNovoEnvioCatalogo() {
    final agora = DateTime.now();
    return {
      'lojaId': lojaId,
      'produtoId': produtoId,
      'nomeCliente': nomeCliente,
      'comentario': comentario,
      'estrelas': estrelas.clamp(1, 5),
      'data': Timestamp.fromDate(data),
      'fotos': fotos,
      'ativo': true,
      'status': CatalogAvaliacaoStatus.pendente.firestoreValue,
      'criadoEm': Timestamp.fromDate(criadoEm ?? agora),
      'aprovadoEm': null,
      'origem': origem ?? 'catalogo_web',
    };
  }

  /// Legado interno / mocks não persistidos — mantido para referência futura.
  Map<String, dynamic> toFirestore() {
    return {
      'lojaId': lojaId,
      'produtoId': produtoId,
      'nomeCliente': nomeCliente,
      'comentario': comentario,
      'estrelas': estrelas.clamp(1, 5),
      'data': Timestamp.fromDate(data),
      'fotos': fotos,
      'ativo': true,
      'status': status.firestoreValue,
      if (criadoEm != null) 'criadoEm': Timestamp.fromDate(criadoEm!),
      if (aprovadoEm != null) 'aprovadoEm': Timestamp.fromDate(aprovadoEm!),
      'origem': origem ?? (isMock ? 'mock' : 'catalogo_web'),
    };
  }
}
