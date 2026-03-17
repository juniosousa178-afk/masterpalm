// lib/catalog/data/firestore_catalog_impl.dart
// Implementação dos contratos do catálogo usando Firestore (MasterPalm atual).
// O PublicCatalogScreen ainda usa Firestore direto; ao refatorar, passará a
// usar estas classes quando não receber fontes injetadas.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/feature_flags.dart';
import '../../core/logger.dart';
import '../../core/safe_cast.dart';
import '../../services/notificacao_vendas_service.dart';
import '../../services/pedido_collection_resolver.dart';
import 'catalog_product_source.dart';
import 'catalog_config_source.dart';
import 'catalog_order_sink.dart';

/// Coleções canônicas do MasterPalm (alinhado com firestore.rules e catalog_helpers)
const String _kLiveProdutosCol = 'produtos';
const String _kDraftProdutosCol = 'draft_produtos';

/// Implementação Firestore de [CatalogProductSource].
class FirestoreCatalogProductSource implements CatalogProductSource {
  FirestoreCatalogProductSource({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<List<Map<String, dynamic>>> watchProducts(
    String lojaId, {
    bool onlyLive = true,
  }) {
    final col = onlyLive ? _kLiveProdutosCol : _kDraftProdutosCol;
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection(col)
        .where('ativo', isEqualTo: true)
        .limit(1000)
        .snapshots()
        .map((snap) => _processDocsToProducts(snap.docs));
  }

  @override
  Future<List<Map<String, dynamic>>> getProducts(
    String lojaId, {
    bool onlyLive = true,
  }) async {
    final col = onlyLive ? _kLiveProdutosCol : _kDraftProdutosCol;
    final snap = await _db
        .collection('lojas')
        .doc(lojaId)
        .collection(col)
        .where('ativo', isEqualTo: true)
        .limit(1000)
        .get();
    return _processDocsToProducts(snap.docs);
  }

  /// Mesmo processamento do PublicCatalogScreen para manter formato esperado pela UI.
  static List<Map<String, dynamic>> _processDocsToProducts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final produtos = <Map<String, dynamic>>[];
    for (final d in docs) {
      final m = asMap(d.data());
      if (m['publicadoNoCatalogo'] == false || m['publicarNoCatalogo'] == false) continue;
      if (m['exibir_no_catalogo'] == false || m['ocultar_catalogo'] == true || m['catalog_ativo'] == false) continue;

      final estoqueRaw = m['estoque'] ?? m['estoqueAtual'] ?? m['qtd_estoque'] ?? m['quantidade'] ?? m['estoque_disponivel'];
      int estoqueBase = 0;
      if (estoqueRaw is num) {
        estoqueBase = estoqueRaw.toInt();
      } else if (estoqueRaw is String) {
        estoqueBase = int.tryParse(estoqueRaw) ?? 0;
      }

      int quantidadeTotal = estoqueBase;
      Map<String, int>? estoquePorTamanho;
      final estoqueTamRaw = m['estoquePorTamanho'];
      if (estoqueTamRaw is Map) {
        estoquePorTamanho = {};
        int somaEstoqueTam = 0;
        estoqueTamRaw.forEach((key, value) {
          final qtd = (value is int) ? value : int.tryParse('$value') ?? 0;
          if (qtd > 0) {
            estoquePorTamanho![key.toString()] = qtd;
            somaEstoqueTam += qtd;
          }
        });
        if (estoquePorTamanho.isNotEmpty && somaEstoqueTam > 0) quantidadeTotal = somaEstoqueTam;
      }

      Map<String, int>? estoquePorCor;
      Map<String, dynamic>? variacoes;
      final variacoesRaw = m['variacoes'];
      if (variacoesRaw is Map && variacoesRaw.isNotEmpty) {
        variacoes = asMapDeep(variacoesRaw);
        int somaVariacoes = 0;
        variacoesRaw.forEach((tamanho, cores) {
          if (cores is Map) {
            cores.forEach((cor, qtd) {
              final q = (qtd is int) ? qtd : int.tryParse('$qtd') ?? 0;
              if (q > 0) somaVariacoes += q;
            });
          }
        });
        if (somaVariacoes > 0) quantidadeTotal = somaVariacoes;
      }
      if (m['estoquePorCor'] is Map) {
        final estoqueCorRaw = asMap(m['estoquePorCor']);
        estoquePorCor = {};
        int somaEstoqueCor = 0;
        estoqueCorRaw.forEach((key, value) {
          final qtd = (value is int) ? value : int.tryParse('$value') ?? 0;
          if (qtd > 0) {
            estoquePorCor![key.toString()] = qtd;
            somaEstoqueCor += qtd;
          }
        });
        if (estoquePorCor.isNotEmpty && somaEstoqueCor > 0 && estoquePorTamanho == null && variacoes == null) quantidadeTotal = somaEstoqueCor;
      }
      if (variacoes != null && variacoes.containsKey('sem-tamanho') && variacoes['sem-tamanho'] is Map) {
        final semTam = variacoes['sem-tamanho'] as Map;
        estoquePorCor ??= {};
        semTam.forEach((key, value) {
          final qtd = (value is int) ? value : int.tryParse('$value') ?? 0;
          if (qtd > 0) estoquePorCor![key.toString()] = qtd;
        });
      }
      final isCombo = m['tipoProduto'] == 'combo';
      if (quantidadeTotal <= 0 && !isCombo) continue;
      if (isCombo && quantidadeTotal <= 0) quantidadeTotal = 1;

      final nome = (m['nome'] ?? m['name'] ?? '').toString();
      final desc = (m['descricao_curta'] ?? m['descricao'] ?? '').toString();
      final precoRaw = m['preco'] ?? m['preco_venda'] ?? m['price'] ?? m['precoFinal'];
      final preco = (precoRaw is num) ? precoRaw.toDouble() : double.tryParse('$precoRaw') ?? 0.0;

      double priceMin = preco;
      double priceMax = preco;
      final ppt = m['precoPorTamanho'];
      if (ppt != null && ppt is Map && ppt.isNotEmpty) {
        final precos = <double>[];
        for (final v in ppt.values) {
          if (v is num) {
            final d = v.toDouble();
            if (d > 0) precos.add(d);
          }
        }
        if (precos.isNotEmpty) {
          priceMin = precos.reduce((a, b) => a < b ? a : b);
          priceMax = precos.reduce((a, b) => a > b ? a : b);
        }
      }
      final categoria = (m['categoria'] ?? m['categoria_nome'] ?? m['categoriaNome'] ?? '').toString().trim();
      final subcategoria = (m['subcategoria'] ?? m['subcategoriaId'] ?? m['subcategoria_nome'] ?? '').toString().trim();

      String principal = (m['imagem_principal'] ?? m['imageUrl'] ?? '').toString();
      final imagens = <String>[];
      final imgsRaw = m['imagens'];
      if (imgsRaw is List) imagens.addAll(imgsRaw.map((e) => e.toString()));
      if (imagens.isEmpty && principal.isNotEmpty) imagens.add(principal);
      if (principal.isEmpty && imagens.isNotEmpty) principal = imagens.first;

      final emPromocao = m['emPromocao'] == true;
      double precoComDesconto = preco;
      double priceMinComPromo = priceMin;
      double priceMaxComPromo = priceMax;
      if (emPromocao) {
        final now = DateTime.now();
        bool promocaoAtiva = true;
        final dataInicio = m['dataInicioPromo'];
        if (dataInicio is Timestamp && now.isBefore(dataInicio.toDate())) promocaoAtiva = false;
        final dataFim = m['dataFimPromo'];
        if (dataFim is Timestamp && now.isAfter(dataFim.toDate())) promocaoAtiva = false;
        if (promocaoAtiva) {
          final percentualPromo = (m['percentualPromo'] is num) ? (m['percentualPromo'] as num).toDouble() : 0.0;
          final valorPromo = (m['valorPromo'] is num) ? (m['valorPromo'] as num).toDouble() : 0.0;
          if (percentualPromo > 0) {
            precoComDesconto = (preco - preco * (percentualPromo / 100)).clamp(0.0, double.infinity);
            priceMinComPromo = (priceMin - priceMin * (percentualPromo / 100)).clamp(0.0, double.infinity);
            priceMaxComPromo = (priceMax - priceMax * (percentualPromo / 100)).clamp(0.0, double.infinity);
          } else if (valorPromo > 0) {
            precoComDesconto = (preco - valorPromo).clamp(0.0, double.infinity);
            priceMinComPromo = (priceMin - valorPromo).clamp(0.0, double.infinity);
            priceMaxComPromo = (priceMax - valorPromo).clamp(0.0, double.infinity);
          }
        }
      }

      DateTime? dataCriacao;
      for (final k in ['createdAt', 'criadoEm', 'dataCadastro']) {
        final v = m[k];
        if (v != null) {
          if (v is Timestamp) { dataCriacao = v.toDate(); break; }
          if (v is DateTime) { dataCriacao = v; break; }
        }
      }
      final isNovo = dataCriacao != null && DateTime.now().difference(dataCriacao).inDays <= 30;

      produtos.add({
        'id': d.id,
        'nome': nome.isEmpty ? 'Produto sem nome' : nome,
        'descricao': desc,
        'preco': emPromocao ? precoComDesconto : preco,
        'precoFinal': preco,
        'priceMin': emPromocao ? priceMinComPromo : priceMin,
        'priceMax': emPromocao ? priceMaxComPromo : priceMax,
        'precoPorTamanho': ppt,
        'imageUrl': principal,
        'imagens': imagens,
        'categoria': categoria,
        'subcategoria': subcategoria,
        'slug': m['slug'] ?? '',
        'peso': (m['peso'] is num) ? (m['peso'] as num).toDouble() : 0.0,
        'tipoEmbalagem': m['tipoEmbalagem'] ?? 'padrao',
        'emPromocao': emPromocao,
        'percentualPromo': (m['percentualPromo'] is num) ? (m['percentualPromo'] as num).toDouble() : 0.0,
        'valorPromo': (m['valorPromo'] is num) ? (m['valorPromo'] as num).toDouble() : 0.0,
        'quantidade': quantidadeTotal,
        'estoquePorTamanho': estoquePorTamanho,
        'estoquePorCor': estoquePorCor,
        'variacoes': variacoes,
        'isNovo': isNovo,
        'dataCriacao': dataCriacao,
        'divideSemJuros': m['divideSemJuros'] == true,
        'maxParcelasSemJuros': (m['maxParcelasSemJuros'] is num) ? (m['maxParcelasSemJuros'] as num).toInt() : 12,
        'percentualDescontoPix': (m['percentualDescontoPix'] is num) ? (m['percentualDescontoPix'] as num).toDouble() : 0.0,
        'videoUrl': (m['videoUrl'] ?? '').toString().trim(),
      });
    }
    return produtos;
  }
}

/// Implementação Firestore de [CatalogConfigSource].
class FirestoreCatalogConfigSource implements CatalogConfigSource {
  FirestoreCatalogConfigSource({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<Map<String, dynamic>> watchConfig(String lojaId) {
    final configRef = _db.collection('lojas').doc(lojaId).collection('config').doc('config');
    final paymentsRef = _db.collection('lojas').doc(lojaId).collection('config').doc('payments');
    return configRef.snapshots().asyncMap((cfgSnap) async {
      final rawCfg = cfgSnap.data();
      final cfg = asMapDeep(rawCfg);
      try {
        final paySnap = await paymentsRef.get();
        if (paySnap.exists && paySnap.data() != null) {
          cfg['payments'] = asMapDeep(paySnap.data());
        }
      } catch (_) {}
      return cfg;
    });
  }

  @override
  Future<Map<String, dynamic>> getConfig(String lojaId) async {
    final snap = await _db
        .collection('lojas')
        .doc(lojaId)
        .collection('config')
        .doc('config')
        .get();
    final raw = snap.data();
    return raw != null ? asMapDeep(raw) : <String, dynamic>{};
  }
}

/// Implementação Firestore de [CatalogOrderSink].
/// Hoje apenas delega: o fluxo real de pedido está em CatalogoVendaService / PrePedidoService.
/// Ao refatorar, mova a lógica de gravar pedido e notificar para dentro deste método.
class FirestoreCatalogOrderSink implements CatalogOrderSink {
  FirestoreCatalogOrderSink({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Future<void> submitOrder(String lojaId, Map<String, dynamic> orderPayload) async {
    final docRef = await PedidoCollectionResolver.collectionRef(
      _db,
      flowType: PedidoFlowType.pedidos,
      lojaId: lojaId,
    ).add({
      ...orderPayload,
      'lojaId': lojaId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // ETAPA 12: Integração CatalogoVendaService (opt-in, flag OFF por padrão)
    if (kEnableCatalogoVendaService) {
      try {
        final clienteNome = _extractClienteNome(orderPayload);
        final valorTotal = _extractValorTotal(orderPayload);
        final vendedorNome = _extractVendedorNome(orderPayload);
        final pagamentoConfirmado = orderPayload['pagamentoConfirmado'] == true ||
            orderPayload['status'] == 'pago' ||
            orderPayload['status'] == 'concluido';

        await NotificacaoVendasService().notificarAdminNovaVenda(
          storeId: lojaId,
          pedidoId: docRef.id,
          clienteNome: clienteNome,
          valorTotal: valorTotal,
          origem: 'catalogo_web',
          vendedorNome: vendedorNome.isNotEmpty ? vendedorNome : null,
          pagamentoConfirmado: pagamentoConfirmado,
        );
        logD('✅ [CatalogOrderSink] Notificação admin enviada para pedido ${docRef.id}');
      } catch (e, st) {
        logE('⚠️ [CatalogOrderSink] Fallback: erro ao integrar CatalogoVendaService (pedido ${docRef.id} já gravado)', error: e, st: st);
      }
    }
  }

  static String _extractClienteNome(Map<String, dynamic> p) {
    final cliente = p['cliente'] ?? p['customer'];
    if (cliente is Map) {
      final n = (cliente['nome'] ?? cliente['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
    return (p['clienteNome'] ?? p['nome'] ?? p['customerName'] ?? 'Cliente').toString().trim();
  }

  static double _extractValorTotal(Map<String, dynamic> p) {
    final v = p['total'] ?? p['valorTotal'] ?? p['valor'] ?? 0;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  static String _extractVendedorNome(Map<String, dynamic> p) {
    return (p['vendedorNome'] ?? p['vendedor'] ?? '').toString().trim();
  }
}
