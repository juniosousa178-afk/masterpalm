// M3.8 Sprint 2 — agregadores read-only de campanhas e roleta (sem engines).

import 'marketing_period_filter.dart';

DateTime? parseMarketingDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  // Timestamp Firestore (sem importar cloud_firestore aqui — duck type)
  try {
    final toDate = (raw as dynamic).toDate;
    if (toDate is Function) {
      final d = toDate();
      if (d is DateTime) return d;
    }
  } catch (_) {}
  if (raw is int) {
    if (raw > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
  }
  if (raw is String) {
    return DateTime.tryParse(raw);
  }
  return null;
}

bool campanhaEstaAtiva(Map<String, dynamic> c, {DateTime? agora}) {
  final now = agora ?? DateTime.now();
  final status = (c['status'] ?? '').toString().trim().toLowerCase();
  if (status == 'sorteada' ||
      status == 'finalizada' ||
      status == 'pausada' ||
      status == 'encerrada') {
    return false;
  }
  final ativaFlag = c['ativa'] == true ||
      status == 'aberta' ||
      status == 'ativa' ||
      status.isEmpty;
  if (!ativaFlag && c['ativa'] != true) return false;
  final inicio = parseMarketingDate(c['dataInicio'] ?? c['criadaEm']);
  final fim = parseMarketingDate(c['dataFim']);
  if (inicio != null && now.isBefore(inicio)) return false;
  if (fim != null && now.isAfter(fim)) return false;
  if (c['ativa'] == true) return true;
  return status == 'aberta' || status == 'ativa' || status.isEmpty;
}

bool campanhaEstaEncerrada(Map<String, dynamic> c, {DateTime? agora}) {
  return !campanhaEstaAtiva(c, agora: agora);
}

int contarNumerosParticipante(Map<String, dynamic> p) {
  final lista = p['numeros'];
  if (lista is List && lista.isNotEmpty) return lista.length;
  final n = p['numeroSorte'] ?? p['numero'];
  if (n == null) return 0;
  final s = n.toString().trim();
  return s.isEmpty ? 0 : 1;
}

bool participanteValido(Map<String, dynamic> p) {
  final st = (p['status'] ?? 'valido').toString().toLowerCase();
  return st != 'cancelado' && st != 'cancelled';
}

double valorParticipacao(Map<String, dynamic> p) {
  final v = p['valorPedido'] ??
      p['valorCompra'] ??
      p['totalVenda'] ??
      p['valor'] ??
      0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

DateTime? dataParticipacao(Map<String, dynamic> p) {
  return parseMarketingDate(
    p['dataParticipacao'] ?? p['criadoEm'] ?? p['dataCompra'],
  );
}

class CampanhaDashboardKpis {
  const CampanhaDashboardKpis({
    required this.ativas,
    required this.encerradas,
    required this.participantes,
    required this.numerosGerados,
    required this.receitaGerada,
    required this.ticketMedio,
    required this.clientesUnicos,
    required this.conversaoPercent,
  });

  final int ativas;
  final int encerradas;
  final int participantes;
  final int numerosGerados;
  final double receitaGerada;
  final double ticketMedio;
  final int clientesUnicos;

  /// participantes / (ativas+encerradas) * 100 — proxy UX; não inventa venda.
  final double conversaoPercent;

  static const zero = CampanhaDashboardKpis(
    ativas: 0,
    encerradas: 0,
    participantes: 0,
    numerosGerados: 0,
    receitaGerada: 0,
    ticketMedio: 0,
    clientesUnicos: 0,
    conversaoPercent: 0,
  );
}

class CampanhaResumoItem {
  const CampanhaResumoItem({
    required this.id,
    required this.nome,
    required this.ativa,
    required this.participantes,
    required this.numeros,
    required this.receita,
  });

  final String id;
  final String nome;
  final bool ativa;
  final int participantes;
  final int numeros;
  final double receita;
}

class CampanhaDashboardSnapshot {
  const CampanhaDashboardSnapshot({
    required this.kpis,
    required this.topCampanhas,
    required this.campanhas,
  });

  final CampanhaDashboardKpis kpis;
  final List<CampanhaResumoItem> topCampanhas;
  final List<CampanhaResumoItem> campanhas;
}

CampanhaDashboardSnapshot agregarDashboardCampanhas({
  required List<Map<String, dynamic>> campanhas,
  required Map<String, List<Map<String, dynamic>>> participantesPorCampanha,
  required MarketingPeriodFilter periodo,
  DateTime? agora,
}) {
  final range = MarketingPeriodRange.resolve(periodo, agora: agora);
  var ativas = 0;
  var encerradas = 0;
  var participantesTot = 0;
  var numerosTot = 0;
  var receitaTot = 0.0;
  final clientes = <String>{};
  final itens = <CampanhaResumoItem>[];

  for (final c in campanhas) {
    final id = (c['id'] ?? '').toString();
    final nome = (c['nome'] ?? c['titulo'] ?? 'Campanha').toString();
    final ativa = campanhaEstaAtiva(c, agora: agora);
    if (ativa) {
      ativas++;
    } else {
      encerradas++;
    }

    final parts = participantesPorCampanha[id] ?? const [];
    var pCount = 0;
    var nCount = 0;
    var receita = 0.0;
    for (final p in parts) {
      if (!participanteValido(p)) continue;
      final dt = dataParticipacao(p);
      if (periodo != MarketingPeriodFilter.todo && !range.contains(dt)) {
        continue;
      }
      pCount++;
      nCount += contarNumerosParticipante(p);
      receita += valorParticipacao(p);
      final cid = (p['clienteId'] ??
              p['clienteTelefone'] ??
              p['telefone'] ??
              p['clienteEmail'] ??
              p['email'] ??
              p['clienteNome'] ??
              p['nomeCliente'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      if (cid.isNotEmpty) clientes.add(cid);
    }
    participantesTot += pCount;
    numerosTot += nCount;
    receitaTot += receita;
    itens.add(
      CampanhaResumoItem(
        id: id,
        nome: nome,
        ativa: ativa,
        participantes: pCount,
        numeros: nCount,
        receita: receita,
      ),
    );
  }

  itens.sort((a, b) => b.receita.compareTo(a.receita));
  final totalCampanhas = ativas + encerradas;
  final conv = totalCampanhas > 0
      ? (participantesTot / totalCampanhas) * 100
      : 0.0;
  final ticket = participantesTot > 0 ? receitaTot / participantesTot : 0.0;

  return CampanhaDashboardSnapshot(
    kpis: CampanhaDashboardKpis(
      ativas: ativas,
      encerradas: encerradas,
      participantes: participantesTot,
      numerosGerados: numerosTot,
      receitaGerada: receitaTot,
      ticketMedio: ticket,
      clientesUnicos: clientes.length,
      conversaoPercent: conv,
    ),
    topCampanhas: itens.take(5).toList(),
    campanhas: itens,
  );
}

class RoletaDashboardKpis {
  const RoletaDashboardKpis({
    required this.giros,
    required this.premios,
    required this.premiosPendentes,
    required this.taxaConversaoPercent,
    required this.valorDistribuido,
    required this.configAtiva,
  });

  final int giros;
  final int premios;
  final int premiosPendentes;
  final double taxaConversaoPercent;
  final double valorDistribuido;
  final bool configAtiva;

  static const zero = RoletaDashboardKpis(
    giros: 0,
    premios: 0,
    premiosPendentes: 0,
    taxaConversaoPercent: 0,
    valorDistribuido: 0,
    configAtiva: false,
  );
}

bool _premioTipoNenhum(String tipo) {
  final t = tipo.toLowerCase().trim();
  return t.isEmpty || t == 'nenhum' || t == 'none' || t == 'sem_premio';
}

double _premioValorNumerico(Map<String, dynamic> log) {
  final v = log['premioValor'] ?? log['valor'] ?? 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

RoletaDashboardKpis agregarDashboardRoleta({
  required Map<String, dynamic>? config,
  required List<Map<String, dynamic>> logs,
  required MarketingPeriodFilter periodo,
  DateTime? agora,
}) {
  final range = MarketingPeriodRange.resolve(periodo, agora: agora);
  final filtrados = logs.where((l) {
    if (periodo == MarketingPeriodFilter.todo) return true;
    final dt = parseMarketingDate(l['criadoEm'] ?? l['createdAt'] ?? l['data']);
    return range.contains(dt);
  }).toList();

  var premios = 0;
  var pendentes = 0;
  var valor = 0.0;
  for (final l in filtrados) {
    final tipo = (l['premioTipo'] ?? l['tipo'] ?? '').toString();
    if (_premioTipoNenhum(tipo)) continue;
    premios++;
    valor += _premioValorNumerico(l);
    final st = (l['status'] ?? '').toString().toLowerCase();
    if (st == 'pendente' || st == 'pending' || st.isEmpty) {
      // sem status = conta como distribuído no log admin; pendente só se explícito
      if (st == 'pendente' || st == 'pending') pendentes++;
    }
  }

  // Pendentes adicionais da config (quantidadeMaxima - quantidadeUsada)
  if (config != null) {
    final premiosCfg = config['premios'];
    if (premiosCfg is List) {
      for (final raw in premiosCfg) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final max = (m['quantidadeMaxima'] as num?)?.toInt() ?? 0;
        final used = (m['quantidadeUsada'] as num?)?.toInt() ?? 0;
        if (max > 0 && used < max) {
          pendentes += (max - used);
        }
      }
    }
  }

  final giros = filtrados.length;
  final taxa = giros > 0 ? (premios / giros) * 100 : 0.0;
  return RoletaDashboardKpis(
    giros: giros,
    premios: premios,
    premiosPendentes: pendentes,
    taxaConversaoPercent: taxa,
    valorDistribuido: valor,
    configAtiva: config?['ativa'] == true,
  );
}

bool roletaHistoricoCorrespondeBusca({
  required Map<String, dynamic> item,
  required String query,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final fields = [
    item['clienteNome'],
    item['clienteTelefone'],
    item['telefone'],
    item['pedidoId'],
    item['vendaId'],
    item['cupom'],
    item['codigoCupom'],
    item['premioLabel'],
    item['premio'],
    item['campanhaNome'],
    item['campanhaId'],
  ];
  for (final f in fields) {
    if (f == null) continue;
    if (f.toString().toLowerCase().contains(q)) return true;
  }
  final digitos = q.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.length >= 3) {
    final tel = (item['clienteTelefone'] ?? item['telefone'] ?? '')
        .toString()
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (tel.contains(digitos)) return true;
  }
  return false;
}

class SeriePonto {
  const SeriePonto({required this.label, required this.valor});
  final String label;
  final double valor;
}

List<SeriePonto> agregarParticipantesPorDia(
  List<Map<String, dynamic>> participantes, {
  required MarketingPeriodFilter periodo,
  DateTime? agora,
}) {
  final range = MarketingPeriodRange.resolve(periodo, agora: agora);
  final map = <String, double>{};
  for (final p in participantes) {
    if (!participanteValido(p)) continue;
    final dt = dataParticipacao(p);
    if (dt == null) continue;
    if (periodo != MarketingPeriodFilter.todo && !range.contains(dt)) continue;
    final key =
        '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    map[key] = (map[key] ?? 0) + 1;
  }
  final keys = map.keys.toList()..sort();
  return [for (final k in keys) SeriePonto(label: k, valor: map[k]!)];
}
