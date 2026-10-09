// Gate autoritativo de campanha de sorteio (número da sorte).
//
// Regra única para qualquer fluxo que gere número / envie "você está concorrendo":
// - exatamente UMA campanha elegível da mesma loja (0 ou >1 ⇒ sem sorteio);
// - elegível: ativa == true, status aberta/ativa (ou ausente), não excluída,
//   dataInicio e dataFim obrigatórias e dataInicio <= agora <= dataFim;
// - falha de consulta ⇒ sem sorteio;
// - participação persistida com id determinístico por venda (idempotente) e
//   janela revalidada com o horário do servidor (`dataParticipacao`), de modo que
//   o relógio do dispositivo não ativa campanha.

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'campaign_engine_service.dart';

enum CampanhaGateStatus { ativa, nenhuma, ambigua, falhaConsulta }

class CampanhaGateResult {
  const CampanhaGateResult._(this.status, {this.campanhaId, this.campanha});

  const CampanhaGateResult.nenhuma() : this._(CampanhaGateStatus.nenhuma);
  const CampanhaGateResult.ambigua() : this._(CampanhaGateStatus.ambigua);
  const CampanhaGateResult.falhaConsulta()
      : this._(CampanhaGateStatus.falhaConsulta);
  const CampanhaGateResult.ativa(String id, Map<String, dynamic> data)
      : this._(CampanhaGateStatus.ativa, campanhaId: id, campanha: data);

  final CampanhaGateStatus status;
  final String? campanhaId;
  final Map<String, dynamic>? campanha;

  bool get permiteSorteio => status == CampanhaGateStatus.ativa;
}

/// Participação persistida e validada (servidor) — única base para e-mail com número.
class ParticipacaoSorteioValidada {
  const ParticipacaoSorteioValidada({
    required this.lojaId,
    required this.campanhaId,
    required this.participacaoId,
    required this.vendaId,
    required this.numero,
    required this.campanha,
    required this.criadaAgora,
  });

  final String lojaId;
  final String campanhaId;
  final String participacaoId;
  final String vendaId;
  final String numero;
  final Map<String, dynamic> campanha;

  /// false quando a participação já existia (retry/idempotência).
  final bool criadaAgora;
}

class CampanhaSorteioGate {
  CampanhaSorteioGate._();

  static FirebaseFirestore? debugFirestoreOverride;

  /// Apenas testes — simula falha/latência da consulta de campanhas.
  static Future<List<({String id, Map<String, dynamic> data})>> Function(
    String lojaId,
  )? debugCampanhasLoader;

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ??
      CampaignEngineService.debugFirestoreOverride ??
      FirebaseFirestore.instance;

  static const Set<String> statusPermitidos = {'aberta', 'ativa', 'active'};

  static CollectionReference<Map<String, dynamic>> _campanhasRef(
    String lojaId,
  ) =>
      _db.collection('lojas').doc(lojaId).collection('campanhas_sorteio');

  static DateTime? _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v.trim());
    return null;
  }

  static bool _excluida(Map<String, dynamic> data) =>
      data['excluida'] == true ||
      data['deleted'] == true ||
      data['isDeleted'] == true ||
      data['deletedAt'] != null ||
      data['excluidaEm'] != null;

  static bool dentroDoPeriodo(Map<String, dynamic> data, DateTime agora) {
    final inicio = _asDate(data['dataInicio']);
    final fim = _asDate(data['dataFim']);
    if (inicio == null || fim == null) return false;
    return !agora.isBefore(inicio) && !agora.isAfter(fim);
  }

  /// Campanha elegível (sem considerar unicidade).
  static bool campanhaElegivel(
    Map<String, dynamic> data, {
    required String lojaId,
    required DateTime agora,
  }) {
    final lojaDoc = (data['lojaId'] ?? '').toString().trim();
    if (lojaDoc.isNotEmpty && lojaDoc != lojaId.trim()) return false;
    if (data['ativa'] != true) return false;
    final rawStatus = data['status'];
    if (rawStatus != null) {
      final s = rawStatus.toString().trim().toLowerCase();
      if (!statusPermitidos.contains(s)) return false;
    }
    if (_excluida(data)) return false;
    return dentroDoPeriodo(data, agora);
  }

  static CampanhaGateResult avaliar(
    Iterable<({String id, Map<String, dynamic> data})> campanhas, {
    required String lojaId,
    required DateTime agora,
  }) {
    final elegiveis = campanhas
        .where((c) => campanhaElegivel(c.data, lojaId: lojaId, agora: agora))
        .toList();
    if (elegiveis.isEmpty) return const CampanhaGateResult.nenhuma();
    if (elegiveis.length > 1) return const CampanhaGateResult.ambigua();
    final c = elegiveis.single;
    return CampanhaGateResult.ativa(c.id, c.data);
  }

  static Future<List<({String id, Map<String, dynamic> data})>> _carregar(
    String lojaId,
  ) async {
    if (debugCampanhasLoader != null) return debugCampanhasLoader!(lojaId);
    final snap = await _campanhasRef(lojaId).limit(100).get();
    return [for (final d in snap.docs) (id: d.id, data: d.data())];
  }

  static Future<CampanhaGateResult> resolver({
    required String lojaId,
    required DateTime agora,
  }) async {
    final li = lojaId.trim();
    if (li.isEmpty) return const CampanhaGateResult.nenhuma();
    try {
      final docs = await _carregar(li);
      return avaliar(docs, lojaId: li, agora: agora);
    } catch (e) {
      debugPrint(
        '⚠️ [CAMPANHA_GATE] consulta falhou (type=${e.runtimeType}) — sem sorteio',
      );
      return const CampanhaGateResult.falhaConsulta();
    }
  }

  static String participacaoDocId(String vendaId) {
    final safe = vendaId.trim().replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    return 'venda_$safe';
  }

  static String _gerarNumero(Random r) => (10000 + r.nextInt(90000)).toString();

  /// Gate + persistência idempotente + revalidação com horário do servidor.
  /// Retorna null quando não há sorteio válido (nenhum e-mail com número).
  static Future<ParticipacaoSorteioValidada?> registrarParticipacaoValidada({
    required String lojaId,
    required String vendaId,
    required double valorCompra,
    required Map<String, dynamic> dadosParticipante,
    DateTime? agora,
    Future<String> Function(String campanhaId)? gerarNumero,
  }) async {
    final li = lojaId.trim();
    final vid = vendaId.trim();
    if (li.isEmpty || vid.isEmpty || vid == '0') return null;

    final gate = await resolver(lojaId: li, agora: agora ?? DateTime.now());
    if (!gate.permiteSorteio) return null;
    final campanhaId = gate.campanhaId!;
    final campanha = gate.campanha!;
    final minimo = (campanha['valorMinimo'] as num?)?.toDouble() ?? 0.0;
    if (valorCompra < minimo) return null;

    try {
      final participantes =
          _campanhasRef(li).doc(campanhaId).collection('participantes');

      for (final campo in const ['pedidoId', 'vendaId']) {
        final legado =
            await participantes.where(campo, isEqualTo: vid).limit(1).get();
        if (legado.docs.isNotEmpty) {
          final d = legado.docs.first;
          return _validarExistente(
            lojaId: li,
            campanhaId: campanhaId,
            campanha: campanha,
            vendaId: vid,
            doc: d,
          );
        }
      }

      // Regras: `get` de participante inexistente é negado (resource == null);
      // a checagem acima é por query e o id determinístico impede duplicata.
      final ref = participantes.doc(participacaoDocId(vid));
      final numero = gerarNumero != null
          ? await gerarNumero(campanhaId)
          : _gerarNumero(Random());
      await ref.set({
        ...dadosParticipante,
        'numeroSorte': numero,
        'campanhaId': campanhaId,
        'lojaId': li,
        'pedidoId': vid,
        'vendaId': vid,
        'valorPedido': valorCompra,
        'dataParticipacao': FieldValue.serverTimestamp(),
        'sorteado': false,
        'status': 'valido',
      });

      final snap = await ref.get();
      if (!snap.exists) return null;
      return _validarExistente(
        lojaId: li,
        campanhaId: campanhaId,
        campanha: campanha,
        vendaId: vid,
        doc: snap,
        criadaAgora: true,
      );
    } catch (e) {
      debugPrint(
        '⚠️ [CAMPANHA_GATE] participação não persistida (type=${e.runtimeType}) — sem sorteio',
      );
      return null;
    }
  }

  static Future<ParticipacaoSorteioValidada?> _validarExistente({
    required String lojaId,
    required String campanhaId,
    required Map<String, dynamic> campanha,
    required String vendaId,
    required DocumentSnapshot<Map<String, dynamic>> doc,
    bool criadaAgora = false,
  }) async {
    final data = doc.data() ?? const <String, dynamic>{};
    final numero =
        (data['numeroSorte'] ?? data['numero'] ?? '').toString().trim();
    final status = (data['status'] ?? 'valido').toString();
    if (numero.isEmpty || status != 'valido') return null;

    final horaServidor = _asDate(data['dataParticipacao']);
    if (horaServidor == null || !dentroDoPeriodo(campanha, horaServidor)) {
      if (criadaAgora) {
        await doc.reference.update({
          'status': 'invalida',
          'motivoInvalidacao': 'fora_do_periodo_servidor',
        });
      }
      return null;
    }

    return ParticipacaoSorteioValidada(
      lojaId: lojaId,
      campanhaId: campanhaId,
      participacaoId: doc.id,
      vendaId: vendaId,
      numero: numero,
      campanha: campanha,
      criadaAgora: criadaAgora,
    );
  }

  @visibleForTesting
  static void resetForTests() {
    debugFirestoreOverride = null;
    debugCampanhasLoader = null;
  }
}
