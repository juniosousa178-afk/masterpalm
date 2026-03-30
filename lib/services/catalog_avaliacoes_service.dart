import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/catalog_avaliacao.dart';
import '../models/catalog_avaliacoes_ordem.dart';

class CatalogAvaliacoesService {
  CatalogAvaliacoesService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Limite de leitura antes de filtrar no cliente (evita índice composto:
  /// `where` + `orderBy` em campos diferentes exige composite index no Firestore).
  static const int _limiteLeitura = 150;

  static CollectionReference<Map<String, dynamic>> _ref(String lojaId) {
    return _db.collection('lojas').doc(lojaId).collection('catalog_avaliacoes');
  }

  /// Query mínima: só [orderBy data] na subcoleção da loja (índice simples automático).
  static Query<Map<String, dynamic>> _queryOrdenadoPorData(String lojaId) {
    return _ref(lojaId.trim())
        .orderBy('data', descending: true)
        .limit(_limiteLeitura);
  }

  static String _normNome(String s) => s.toLowerCase().trim();

  /// Reordena cópia da lista para exibição no catálogo (não altera a lista original).
  static List<CatalogAvaliacao> aplicarOrdem(
    List<CatalogAvaliacao> lista,
    CatalogAvaliacoesOrdem ordem,
  ) {
    final copy = List<CatalogAvaliacao>.from(lista);
    switch (ordem) {
      case CatalogAvaliacoesOrdem.maisRecentes:
        copy.sort((a, b) => b.data.compareTo(a.data));
        break;
      case CatalogAvaliacoesOrdem.maisAntigas:
        copy.sort((a, b) => a.data.compareTo(b.data));
        break;
      case CatalogAvaliacoesOrdem.melhorAvaliadas:
        copy.sort((a, b) {
          final c = b.estrelas.compareTo(a.estrelas);
          if (c != 0) return c;
          return b.data.compareTo(a.data);
        });
        break;
      case CatalogAvaliacoesOrdem.pioresAvaliadas:
        copy.sort((a, b) {
          final c = a.estrelas.compareTo(b.estrelas);
          if (c != 0) return c;
          return b.data.compareTo(a.data);
        });
        break;
      case CatalogAvaliacoesOrdem.nomeAz:
        copy.sort(
          (a, b) => _normNome(a.nomeCliente).compareTo(_normNome(b.nomeCliente)),
        );
        break;
      case CatalogAvaliacoesOrdem.nomeZa:
        copy.sort(
          (a, b) => _normNome(b.nomeCliente).compareTo(_normNome(a.nomeCliente)),
        );
        break;
    }
    return copy;
  }

  static bool _docPassaFiltroLoja(
    Map<String, dynamic> m,
    String lojaId, {
    String? produtoId,
  }) {
    if (m['ativo'] == false) return false;
    if ((m['lojaId'] ?? '').toString().trim() != lojaId.trim()) return false;
    final p = produtoId?.trim();
    if (p != null && p.isNotEmpty) {
      final docPid = (m['produtoId'] ?? '').toString().trim();
      if (docPid != p) return false;
    }
    return true;
  }

  static Stream<List<CatalogAvaliacao>> watchByLoja(
    String lojaId, {
    String? produtoId,
  }) {
    if (lojaId.trim().isEmpty) {
      return Stream.value(const <CatalogAvaliacao>[]);
    }

    final lid = lojaId.trim();
    return _queryOrdenadoPorData(lid).snapshots().map((snap) {
      final docs = snap.docs
          .where((d) => _docPassaFiltroLoja(d.data(), lid, produtoId: produtoId))
          .map((d) => CatalogAvaliacao.fromFirestore(d.id, d.data()))
          .where((a) => a.visivelNoCatalogoPublico)
          .toList()
        ..sort((a, b) => b.data.compareTo(a.data));

      final top = docs.take(30).toList();
      if (top.isNotEmpty) return top;
      return _mockAvaliacoes(lid);
    }).handleError((_) {
      return _mockAvaliacoes(lid);
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
  /// Filtra `ativo`, `lojaId` e `pendente` no app (evita índice composto no Firestore).
  static Stream<List<CatalogAvaliacao>> watchPendentesPorLoja(String lojaId) {
    if (lojaId.trim().isEmpty) {
      return Stream.value(const <CatalogAvaliacao>[]);
    }
    final id = lojaId.trim();
    return _queryOrdenadoPorData(id).snapshots().map((snap) {
      return snap.docs
          .where((d) => _docPassaFiltroLoja(d.data(), id))
          .map((d) => CatalogAvaliacao.fromFirestore(d.id, d.data()))
          .where((a) => a.status == CatalogAvaliacaoStatus.pendente)
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
