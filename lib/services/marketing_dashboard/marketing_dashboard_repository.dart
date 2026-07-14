// M3.8 Sprint 2 — repositório somente leitura (Campanhas / Roleta).
// Não chama CampaignEngine onVenda nem altera configs.
// R2: degradação segura quando roleta_vendas for permission-denied.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../campanhas_sorteio_service.dart';
import 'firestore_client_error.dart';
import 'marketing_dashboard_aggregators.dart';
import 'marketing_period_filter.dart';

/// Fetch de logs: [orderBy]==true usa orderBy('criadoEm'); false = listagem simples.
typedef RoletaLogsQuery = Future<List<Map<String, dynamic>>> Function(
  String lojaId, {
  required bool orderBy,
});

class MarketingDashboardRepository {
  MarketingDashboardRepository({
    FirebaseFirestore? db,
    RoletaLogsQuery? roletaLogsQuery,
  })  : _db = db,
        _roletaLogsQuery = roletaLogsQuery ?? _defaultRoletaLogsQuery;

  final FirebaseFirestore? _db;
  final RoletaLogsQuery _roletaLogsQuery;

  /// Contador de tentativas de query sem orderBy (testes PERM-2/3).
  @visibleForTesting
  int debugFallbackSemOrderByCount = 0;

  static Future<List<Map<String, dynamic>>> _defaultRoletaLogsQuery(
    String lojaId, {
    required bool orderBy,
  }) async {
    final ref = CampanhasSorteioService.roletaLogsRef(lojaId);
    final QuerySnapshot<Map<String, dynamic>> snap;
    if (orderBy) {
      snap = await ref.orderBy('criadoEm', descending: true).limit(500).get();
    } else {
      snap = await ref.limit(500).get();
    }
    return snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
  }

  CollectionReference<Map<String, dynamic>> _campanhas(String lojaId) {
    final override = _db;
    if (override != null) {
      return override
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio');
    }
    return CampanhasSorteioService.campanhasRef(lojaId);
  }

  Future<List<Map<String, dynamic>>> listarCampanhas(String lojaId) async {
    final snap = await _campanhas(lojaId).get();
    return snap.docs
        .map((d) => {...d.data(), 'id': d.id})
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listarParticipantesCampanha({
    required String lojaId,
    required String campanhaId,
  }) async {
    final snap = await _campanhas(lojaId)
        .doc(campanhaId)
        .collection('participantes')
        .get();
    return snap.docs
        .map((d) => {...d.data(), 'id': d.id, 'campanhaId': campanhaId})
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listarHistoricoSorteio({
    required String lojaId,
    required String campanhaId,
  }) async {
    final snap = await _campanhas(lojaId)
        .doc(campanhaId)
        .collection('historico_sorteios')
        .get();
    return snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
  }

  Future<Map<String, dynamic>?> obterCampanha({
    required String lojaId,
    required String campanhaId,
  }) async {
    final doc = await _campanhas(lojaId).doc(campanhaId).get();
    if (!doc.exists) return null;
    return {...?doc.data(), 'id': doc.id};
  }

  Future<Map<String, dynamic>?> carregarConfigRoleta(String lojaId) {
    return CampanhasSorteioService.carregarConfigRoleta(lojaId: lojaId);
  }

  /// Lista logs com fallback **somente** para failed-precondition (índice).
  /// Em permission-denied NÃO reexecuta a query.
  Future<RoletaLogsLoadResult> listarLogsRoletaResult(String lojaId) async {
    try {
      final logs = await _roletaLogsQuery(lojaId, orderBy: true);
      return RoletaLogsLoadResult(
        logs: logs,
        historicoDisponivel: true,
        availability: logs.isEmpty
            ? MarketingMetricAvailability.empty
            : MarketingMetricAvailability.available,
      );
    } catch (e) {
      final kind = classifyFirestoreClientError(e);
      if (kind == FirestoreClientErrorKind.permissionDenied) {
        return RoletaLogsLoadResult(
          logs: const [],
          historicoDisponivel: false,
          availability: MarketingMetricAvailability.permissionDenied,
          indisponibilidadeCodigo: 'permission-denied',
          error: e,
        );
      }
      if (kind == FirestoreClientErrorKind.failedPrecondition) {
        try {
          debugFallbackSemOrderByCount++;
          final logs = await _roletaLogsQuery(lojaId, orderBy: false);
          return RoletaLogsLoadResult(
            logs: logs,
            historicoDisponivel: true,
            availability: logs.isEmpty
                ? MarketingMetricAvailability.empty
                : MarketingMetricAvailability.available,
          );
        } catch (e2) {
          if (isFirestorePermissionDenied(e2)) {
            return RoletaLogsLoadResult(
              logs: const [],
              historicoDisponivel: false,
              availability: MarketingMetricAvailability.permissionDenied,
              indisponibilidadeCodigo: 'permission-denied',
              error: e2,
            );
          }
          return RoletaLogsLoadResult(
            logs: const [],
            historicoDisponivel: false,
            availability: MarketingMetricAvailability.error,
            indisponibilidadeCodigo:
                classifyFirestoreClientError(e2).name,
            error: e2,
          );
        }
      }
      return RoletaLogsLoadResult(
        logs: const [],
        historicoDisponivel: false,
        availability: MarketingMetricAvailability.error,
        indisponibilidadeCodigo: kind.name,
        error: e,
      );
    }
  }

  /// Compat: lança se indisponível; preferir [listarLogsRoletaResult].
  Future<List<Map<String, dynamic>>> listarLogsRoleta(String lojaId) async {
    final r = await listarLogsRoletaResult(lojaId);
    if (!r.historicoDisponivel && r.error != null) {
      throw r.error!;
    }
    return r.logs;
  }

  Future<CampanhaDashboardSnapshot> carregarDashboardCampanhas({
    required String lojaId,
    required MarketingPeriodFilter periodo,
  }) async {
    final campanhas = await listarCampanhas(lojaId);
    final mapa = <String, List<Map<String, dynamic>>>{};
    for (final c in campanhas) {
      final id = (c['id'] ?? '').toString();
      if (id.isEmpty) continue;
      mapa[id] = await listarParticipantesCampanha(
        lojaId: lojaId,
        campanhaId: id,
      );
    }
    return agregarDashboardCampanhas(
      campanhas: campanhas,
      participantesPorCampanha: mapa,
      periodo: periodo,
    );
  }

  /// Config + logs. Permission-denied em logs NÃO derruba a config.
  Future<RoletaDashboardLoadResult> carregarDashboardRoleta({
    required String lojaId,
    required MarketingPeriodFilter periodo,
  }) async {
    final config = await carregarConfigRoleta(lojaId);
    final logsResult = await listarLogsRoletaResult(lojaId);

    if (!logsResult.historicoDisponivel &&
        logsResult.availability ==
            MarketingMetricAvailability.permissionDenied) {
      return RoletaDashboardLoadResult(
        config: config,
        logs: const [],
        historicoDisponivel: false,
        indisponibilidadeCodigo: 'permission-denied',
        kpis: RoletaDashboardKpis.fromConfigOnly(config),
      );
    }

    if (!logsResult.historicoDisponivel) {
      return RoletaDashboardLoadResult(
        config: config,
        logs: const [],
        historicoDisponivel: false,
        indisponibilidadeCodigo:
            logsResult.indisponibilidadeCodigo ?? 'error',
        kpis: RoletaDashboardKpis.fromConfigOnly(config),
      );
    }

    final kpis = agregarDashboardRoleta(
      config: config,
      logs: logsResult.logs,
      periodo: periodo,
      logsDisponiveis: true,
    );
    return RoletaDashboardLoadResult(
      config: config,
      logs: logsResult.logs,
      historicoDisponivel: true,
      kpis: kpis,
    );
  }

  /// Série diária simples (participantes de todas as campanhas no período).
  Future<List<SeriePonto>> carregarParticipantesPorDia({
    required String lojaId,
    required MarketingPeriodFilter periodo,
  }) async {
    final campanhas = await listarCampanhas(lojaId);
    final all = <Map<String, dynamic>>[];
    for (final c in campanhas) {
      final id = (c['id'] ?? '').toString();
      if (id.isEmpty) continue;
      all.addAll(await listarParticipantesCampanha(
        lojaId: lojaId,
        campanhaId: id,
      ));
    }
    return agregarParticipantesPorDia(all, periodo: periodo);
  }
}
