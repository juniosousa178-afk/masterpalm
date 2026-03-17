// lib/services/globo_sorteio_params_resolver.dart
// Resolve lojaId e campanhaId para a tela Globo Sorteio (ETAPA 18). Sem placeholders em produção.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/logger.dart';
import 'loja_id_service.dart';
import 'store_resolver_facade.dart';

/// Parâmetros resolvidos para a tela Globo Sorteio.
class GloboSorteioParams {
  final String lojaId;
  final String campanhaId;
  final String? source;

  const GloboSorteioParams({
    required this.lojaId,
    required this.campanhaId,
    this.source,
  });
}

const Duration _timeout = Duration(seconds: 10);

class GloboSorteioParamsResolver {
  GloboSorteioParamsResolver._();

  static final _db = FirebaseFirestore.instance;

  /// Resolve lojaId e campanhaId: URL (query/fragment) > LojaIdService/StoreResolver > Firestore campanha ativa.
  /// Retorna null em erro/timeout (caller deve fallback ou mostrar erro).
  static Future<GloboSorteioParams?> resolve({
    required Uri uri,
    required bool isWeb,
  }) async {
    try {
      String? lojaId = _lojaIdFromUri(uri);
      String? campanhaId = _campanhaIdFromUri(uri);
      String? source = 'uri';

      if (lojaId == null || lojaId.trim().isEmpty) {
        logW('[GloboSorteioParams] lojaId não veio da URL; buscando contexto', tag: 'GLOBO_SORTEIO');
        final fromService = (await LojaIdService.get())?.trim();
        lojaId = (fromService != null && fromService.isNotEmpty)
            ? fromService
            : (await StoreResolverFacade.resolveForAdminApp())?.trim();
        source = 'context';
      }
      if (lojaId == null || lojaId.trim().isEmpty) {
        logE('[GloboSorteioParams] Não foi possível obter lojaId', tag: 'GLOBO_SORTEIO');
        return null;
      }
      lojaId = lojaId.trim();

      if (campanhaId == null || campanhaId.trim().isEmpty) {
        logW('[GloboSorteioParams] campanhaId não veio da URL; buscando campanha ativa', tag: 'GLOBO_SORTEIO');
        campanhaId = await _buscarCampanhaAtiva(lojaId);
        if (campanhaId != null) source = 'firestore';
      }
      if (campanhaId == null || campanhaId.trim().isEmpty) {
        logW('[GloboSorteioParams] Nenhuma campanha ativa para loja', tag: 'GLOBO_SORTEIO');
        return null;
      }
      campanhaId = campanhaId.trim();

      logD('[GloboSorteioParams] source=$source', tag: 'GLOBO_SORTEIO');
      return GloboSorteioParams(lojaId: lojaId, campanhaId: campanhaId, source: source);
    } on TimeoutException catch (e, st) {
      logE('[GloboSorteioParams] Timeout', tag: 'GLOBO_SORTEIO', error: e, st: st);
      return null;
    } catch (e, st) {
      logE('[GloboSorteioParams] Erro ao resolver', tag: 'GLOBO_SORTEIO', error: e, st: st);
      return null;
    }
  }

  static String? _lojaIdFromUri(Uri uri) {
    final q = uri.queryParameters;
    final v = q['lojaId'] ?? q['loja_id'] ?? q['store'] ?? q['storeId'];
    if (v != null && v.trim().isNotEmpty) return v.trim();
    final f = uri.fragment;
    if (f.isNotEmpty) {
      final params = Uri.splitQueryString(f);
      final vf = params['lojaId'] ?? params['loja_id'] ?? params['store'] ?? params['storeId'];
      if (vf != null && vf.trim().isNotEmpty) return vf.trim();
    }
    return null;
  }

  static String? _campanhaIdFromUri(Uri uri) {
    final q = uri.queryParameters;
    final v = q['campanhaId'] ?? q['campanha_id'] ?? q['campaign'] ?? q['campanha'];
    if (v != null && v.trim().isNotEmpty) return v.trim();
    final f = uri.fragment;
    if (f.isNotEmpty) {
      final params = Uri.splitQueryString(f);
      final vf = params['campanhaId'] ?? params['campanha_id'] ?? params['campaign'] ?? params['campanha'];
      if (vf != null && vf.trim().isNotEmpty) return vf.trim();
    }
    return null;
  }

  /// Busca uma campanha ativa em lojas/{lojaId}/campanhas_sorteio (mesmo critério de loja_config_screen).
  static Future<String?> _buscarCampanhaAtiva(String lojaId) async {
    final snap = await _db
        .collection('lojas')
        .doc(lojaId)
        .collection('campanhas_sorteio')
        .limit(50)
        .get()
        .timeout(_timeout);

    final now = DateTime.now();
    for (final doc in snap.docs) {
      final data = doc.data();
      final isAtiva = data['ativa'] == true ||
          data['status'] == 'aberta' ||
          data['status'] == 'ativa';
      if (!isAtiva) continue;

      final dataInicio = (data['dataInicio'] as Timestamp?)?.toDate();
      final dataFim = (data['dataFim'] as Timestamp?)?.toDate();
      final dentroDoInicio = dataInicio == null ||
          dataInicio.isBefore(now) ||
          dataInicio.isAtSameMomentAs(now);
      final dentroDoFim = dataFim == null || dataFim.isAfter(now);
      if (dentroDoInicio && dentroDoFim) return doc.id;
    }
    return null;
  }
}
