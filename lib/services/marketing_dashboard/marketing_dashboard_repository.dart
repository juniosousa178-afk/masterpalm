// M3.8 Sprint 2 — repositório somente leitura (Campanhas / Roleta).
// Não chama CampaignEngine onVenda nem altera configs.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../campanhas_sorteio_service.dart';
import 'marketing_dashboard_aggregators.dart';
import 'marketing_period_filter.dart';

class MarketingDashboardRepository {
  MarketingDashboardRepository({FirebaseFirestore? db}) : _db = db;

  final FirebaseFirestore? _db;

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

  Future<List<Map<String, dynamic>>> listarLogsRoleta(String lojaId) async {
    final snap = await CampanhasSorteioService.roletaLogsRef(lojaId)
        .orderBy('criadoEm', descending: true)
        .limit(500)
        .get();
    return snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
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

  Future<RoletaDashboardKpis> carregarDashboardRoleta({
    required String lojaId,
    required MarketingPeriodFilter periodo,
  }) async {
    final config = await carregarConfigRoleta(lojaId);
    List<Map<String, dynamic>> logs;
    try {
      logs = await listarLogsRoleta(lojaId);
    } catch (_) {
      // Fallback sem orderBy se índice ausente
      final snap =
          await CampanhasSorteioService.roletaLogsRef(lojaId).limit(500).get();
      logs = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    }
    return agregarDashboardRoleta(
      config: config,
      logs: logs,
      periodo: periodo,
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
