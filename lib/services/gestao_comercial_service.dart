// M3.9 SPRINT4 — persistência app de gestão comercial (sem tocar Rules/Functions).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/gestao_comercial.dart';
import 'comercial_audit_log_service.dart';

abstract final class GestaoComercialService {
  GestaoComercialService._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  @visibleForTesting
  static final Map<String, GestaoVendedorConfig> debugConfigCache = {};

  @visibleForTesting
  static final Map<String, ProdutoAcessoComercial> debugProdutoCache = {};

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  static String _vk(String lojaId, String uid) =>
      '${lojaId.trim()}|${uid.trim()}';

  static String _pk(String lojaId, String productId) =>
      '${lojaId.trim()}|${productId.trim()}';

  static DocumentReference<Map<String, dynamic>> _vendedorRef(
    String lojaId,
    String uid,
  ) =>
      _db
          .collection('lojas')
          .doc(lojaId.trim())
          .collection('vendedores')
          .doc(uid.trim());

  static DocumentReference<Map<String, dynamic>> _produtoAcessoRef(
    String lojaId,
    String productId,
  ) =>
      _db
          .collection('lojas')
          .doc(lojaId.trim())
          .collection('comercial_produtos')
          .doc(productId.trim());

  static Future<GestaoVendedorConfig> carregarConfigVendedor({
    required String lojaId,
    required String vendedorUid,
  }) async {
    final key = _vk(lojaId, vendedorUid);
    if (debugFirestoreOverride == null && debugConfigCache.containsKey(key)) {
      // cache opcional em memória (também usada em testes)
    }
    if (debugConfigCache.containsKey(key)) {
      return debugConfigCache[key]!;
    }
    try {
      final snap = await _vendedorRef(lojaId, vendedorUid).get();
      final data = snap.data();
      final gestao = data?['gestao'];
      final cfg = GestaoVendedorConfig.fromMap(
        gestao is Map ? Map<String, dynamic>.from(gestao) : null,
      );
      debugConfigCache[key] = cfg;
      return cfg;
    } catch (e) {
      debugPrint('[GESTAO] carregarConfig fail type=${e.runtimeType}');
      final fallback =
          GestaoVendedorConfig(permissoes: GestaoVendedorConfig.permissoesPadraoVendedor());
      debugConfigCache[key] = fallback;
      return fallback;
    }
  }

  static Future<void> salvarConfigVendedor({
    required String lojaId,
    required String vendedorUid,
    required GestaoVendedorConfig config,
    required String atorUid,
    GestaoVendedorConfig? anterior,
  }) async {
    final key = _vk(lojaId, vendedorUid);
    debugConfigCache[key] = config;
    try {
      await _vendedorRef(lojaId, vendedorUid).set({
        'gestao': config.toMap(),
        'comissaoPercentual': config.comissaoPercentual,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[GESTAO] salvarConfig fail type=${e.runtimeType}');
      rethrow;
    }

    if (anterior != null) {
      if (anterior.metaMensal != config.metaMensal ||
          anterior.metaDiaria != config.metaDiaria ||
          anterior.metaAnual != config.metaAnual) {
        await ComercialAuditLogService.log(
          lojaId: lojaId,
          acao: 'alteracao_meta',
          atorUid: atorUid,
          alvoVendedorUid: vendedorUid,
          detalhe: {
            'metaMensal': config.metaMensal,
            'metaDiaria': config.metaDiaria,
            'metaAnual': config.metaAnual,
          },
        );
      }
      if (anterior.comissaoTipo != config.comissaoTipo ||
          anterior.comissaoPercentual != config.comissaoPercentual ||
          anterior.comissaoValorFixo != config.comissaoValorFixo) {
        await ComercialAuditLogService.log(
          lojaId: lojaId,
          acao: 'alteracao_comissao',
          atorUid: atorUid,
          alvoVendedorUid: vendedorUid,
          detalhe: {
            'tipo': config.comissaoTipo.wireValue,
            'pct': config.comissaoPercentual,
          },
        );
      }
      if (!_mapsEq(anterior.permissoes, config.permissoes)) {
        await ComercialAuditLogService.log(
          lojaId: lojaId,
          acao: 'permissao_alterada',
          atorUid: atorUid,
          alvoVendedorUid: vendedorUid,
        );
      }
    } else {
      await ComercialAuditLogService.log(
        lojaId: lojaId,
        acao: 'config_salva',
        atorUid: atorUid,
        alvoVendedorUid: vendedorUid,
      );
    }
  }

  static Future<ProdutoAcessoComercial> carregarProdutoAcesso({
    required String lojaId,
    required String productId,
  }) async {
    final key = _pk(lojaId, productId);
    if (debugProdutoCache.containsKey(key)) return debugProdutoCache[key]!;
    try {
      final snap = await _produtoAcessoRef(lojaId, productId).get();
      final cfg = ProdutoAcessoComercial.fromMap(productId, snap.data());
      debugProdutoCache[key] = cfg;
      return cfg;
    } catch (e) {
      debugPrint('[GESTAO] produtoAcesso fail type=${e.runtimeType}');
      final empty = ProdutoAcessoComercial(productId: productId);
      debugProdutoCache[key] = empty;
      return empty;
    }
  }

  static Future<void> salvarProdutoAcesso({
    required String lojaId,
    required ProdutoAcessoComercial acesso,
    required String atorUid,
    ProdutoAcessoComercial? anterior,
  }) async {
    final key = _pk(lojaId, acesso.productId);
    debugProdutoCache[key] = acesso;
    try {
      await _produtoAcessoRef(lojaId, acesso.productId).set(
        {
          ...acesso.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[GESTAO] salvarProduto fail type=${e.runtimeType}');
      rethrow;
    }

    final antB = (anterior?.bloqueados ?? const []).toSet();
    final novoB = acesso.bloqueados.toSet();
    for (final u in novoB.difference(antB)) {
      await ComercialAuditLogService.log(
        lojaId: lojaId,
        acao: 'produto_ocultado',
        atorUid: atorUid,
        alvoVendedorUid: u,
        produtoId: acesso.productId,
      );
    }
    for (final u in antB.difference(novoB)) {
      await ComercialAuditLogService.log(
        lojaId: lojaId,
        acao: 'produto_liberado',
        atorUid: atorUid,
        alvoVendedorUid: u,
        produtoId: acesso.productId,
      );
    }
  }

  static Future<void> registrarDescontoAutorizado({
    required String lojaId,
    required String atorUid,
    required String vendedorUid,
    required double descontoPct,
  }) {
    return ComercialAuditLogService.log(
      lojaId: lojaId,
      acao: 'desconto_autorizado',
      atorUid: atorUid,
      alvoVendedorUid: vendedorUid,
      detalhe: {'descontoPct': descontoPct},
    );
  }

  static Future<void> registrarAtivacao({
    required String lojaId,
    required String atorUid,
    required String vendedorUid,
    required bool ativo,
  }) {
    return ComercialAuditLogService.log(
      lojaId: lojaId,
      acao: ativo ? 'vendedor_ativado' : 'vendedor_desativado',
      atorUid: atorUid,
      alvoVendedorUid: vendedorUid,
    );
  }

  /// Leitura síncrona do cache de acesso (após preload / testes).
  static ProdutoAcessoComercial acessoProdutoDoCache({
    required String lojaId,
    required String productId,
  }) {
    final key = _pk(lojaId, productId);
    return debugProdutoCache[key] ??
        ProdutoAcessoComercial(productId: productId.trim());
  }

  /// Pré-carrega listas permitidos/bloqueados para filtragem síncrona na UI.
  /// Concorrência limitada (evita N awaits seriais).
  static Future<void> preloadProdutoAcessos({
    required String lojaId,
    required Iterable<String> productIds,
    int concurrency = 8,
  }) async {
    final seen = <String>{};
    final ids = <String>[];
    for (final raw in productIds) {
      final id = raw.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      ids.add(id);
    }
    if (ids.isEmpty) return;
    final limit = concurrency < 1 ? 1 : concurrency;
    var i = 0;
    while (i < ids.length) {
      final end = (i + limit > ids.length) ? ids.length : i + limit;
      final chunk = ids.sublist(i, end);
      await Future.wait([
        for (final id in chunk)
          carregarProdutoAcesso(lojaId: lojaId, productId: id),
      ]);
      i = end;
    }
  }

  static void clearCaches() {
    debugConfigCache.clear();
    debugProdutoCache.clear();
  }

  static bool _mapsEq(Map<String, bool> a, Map<String, bool> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}
