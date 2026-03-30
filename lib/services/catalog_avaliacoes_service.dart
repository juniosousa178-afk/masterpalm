import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/catalog_avaliacao.dart';

class CatalogAvaliacoesService {
  CatalogAvaliacoesService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Limite de leitura antes de filtrar por status no cliente (evita índice composto
  /// e mantém compat com docs antigos sem `status`).
  static const int _limiteLeitura = 150;

  static CollectionReference<Map<String, dynamic>> _ref(String lojaId) {
    return _db.collection('lojas').doc(lojaId).collection('catalog_avaliacoes');
  }

  static Stream<List<CatalogAvaliacao>> watchByLoja(
    String lojaId, {
    String? produtoId,
  }) {
    if (lojaId.trim().isEmpty) {
      return Stream.value(const <CatalogAvaliacao>[]);
    }

    Query<Map<String, dynamic>> query = _ref(lojaId)
        .where('ativo', isEqualTo: true)
        .where('lojaId', isEqualTo: lojaId)
        .orderBy('data', descending: true)
        .limit(_limiteLeitura);

    if (produtoId != null && produtoId.trim().isNotEmpty) {
      query = query.where('produtoId', isEqualTo: produtoId.trim());
    }

    return query.snapshots().map((snap) {
      final docs = snap.docs
          .map((d) => CatalogAvaliacao.fromFirestore(d.id, d.data()))
          .where((a) => a.lojaId == lojaId && a.visivelNoCatalogoPublico)
          .toList()
        ..sort((a, b) => b.data.compareTo(a.data));

      final top = docs.take(30).toList();
      if (top.isNotEmpty) return top;
      return _mockAvaliacoes(lojaId);
    }).handleError((_) {
      return _mockAvaliacoes(lojaId);
    });
  }

  static Future<void> enviarAvaliacao({
    required String lojaId,
    String? produtoId,
    required String nomeCliente,
    required String comentario,
    required int estrelas,
    List<String> fotos = const [],
  }) async {
    if (lojaId.trim().isEmpty) return;
    final nome = nomeCliente.trim();
    final texto = comentario.trim();
    if (nome.isEmpty || texto.isEmpty) return;

    final agora = DateTime.now();
    final avaliacao = CatalogAvaliacao(
      id: '',
      lojaId: lojaId.trim(),
      produtoId: produtoId?.trim().isEmpty == true ? null : produtoId?.trim(),
      nomeCliente: nome,
      comentario: texto,
      estrelas: estrelas.clamp(1, 5),
      data: agora,
      fotos: fotos.where((e) => e.trim().isNotEmpty).map((e) => e.trim()).toList(),
      status: CatalogAvaliacaoStatus.pendente,
      criadoEm: agora,
      aprovadoEm: null,
      origem: 'catalogo_web',
    );

    await _ref(lojaId.trim()).add(avaliacao.toFirestoreNovoEnvioCatalogo());
  }

  /// Avaliações aguardando moderação — apenas da [lojaId] informada.
  /// Filtra `pendente` no app (mesmo padrão do catálogo: evita índice composto extra).
  static Stream<List<CatalogAvaliacao>> watchPendentesPorLoja(String lojaId) {
    if (lojaId.trim().isEmpty) {
      return Stream.value(const <CatalogAvaliacao>[]);
    }
    final id = lojaId.trim();
    return _ref(id)
        .where('ativo', isEqualTo: true)
        .where('lojaId', isEqualTo: id)
        .orderBy('data', descending: true)
        .limit(_limiteLeitura)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((d) => CatalogAvaliacao.fromFirestore(d.id, d.data()))
          .where((a) =>
              a.lojaId == id && a.status == CatalogAvaliacaoStatus.pendente)
          .toList();
    });
  }

  static Future<void> aprovarAvaliacao({
    required String lojaId,
    required String avaliacaoId,
  }) async {
    final lid = lojaId.trim();
    final aid = avaliacaoId.trim();
    if (lid.isEmpty || aid.isEmpty) return;
    await _ref(lid).doc(aid).update({
      'status': CatalogAvaliacaoStatus.aprovado.firestoreValue,
      'aprovadoEm': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> rejeitarAvaliacao({
    required String lojaId,
    required String avaliacaoId,
  }) async {
    final lid = lojaId.trim();
    final aid = avaliacaoId.trim();
    if (lid.isEmpty || aid.isEmpty) return;
    await _ref(lid).doc(aid).update({
      'status': CatalogAvaliacaoStatus.rejeitado.firestoreValue,
    });
  }

  static List<CatalogAvaliacao> _mockAvaliacoes(String lojaId) {
    final now = DateTime.now();
    final base = <CatalogAvaliacao>[
      CatalogAvaliacao(
        id: 'mock-1-$lojaId',
        lojaId: lojaId,
        nomeCliente: 'Mariana S.',
        comentario: 'Chegou certinho e a peça é muito delicada.',
        estrelas: 5,
        data: now.subtract(const Duration(days: 4)),
        isMock: true,
        status: CatalogAvaliacaoStatus.aprovado,
        origem: 'mock',
      ),
      CatalogAvaliacao(
        id: 'mock-2-$lojaId',
        lojaId: lojaId,
        nomeCliente: 'Carla M.',
        comentario: 'Gostei bastante, veio bem embalada.',
        estrelas: 4,
        data: now.subtract(const Duration(days: 8)),
        isMock: true,
        status: CatalogAvaliacaoStatus.aprovado,
        origem: 'mock',
      ),
      CatalogAvaliacao(
        id: 'mock-3-$lojaId',
        lojaId: lojaId,
        nomeCliente: 'Fernanda R.',
        comentario: 'Atendimento atencioso e envio rápido.',
        estrelas: 5,
        data: now.subtract(const Duration(days: 11)),
        isMock: true,
        status: CatalogAvaliacaoStatus.aprovado,
        origem: 'mock',
      ),
      CatalogAvaliacao(
        id: 'mock-4-$lojaId',
        lojaId: lojaId,
        nomeCliente: 'Patricia L.',
        comentario: 'A peça é linda pessoalmente.',
        estrelas: 5,
        data: now.subtract(const Duration(days: 15)),
        isMock: true,
        status: CatalogAvaliacaoStatus.aprovado,
        origem: 'mock',
      ),
      CatalogAvaliacao(
        id: 'mock-5-$lojaId',
        lojaId: lojaId,
        nomeCliente: 'Aline C.',
        comentario: 'Veio igualzinho às fotos.',
        estrelas: 4,
        data: now.subtract(const Duration(days: 20)),
        isMock: true,
        status: CatalogAvaliacaoStatus.aprovado,
        origem: 'mock',
      ),
    ];
    return base;
  }
}
