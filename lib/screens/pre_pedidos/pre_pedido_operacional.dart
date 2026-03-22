// Classificação derivada só para UI do painel admin — sem escrita no Firestore.
// Limiar de "abandono potencial": 72h desde a última atividade conhecida (dataCriacao/dataAtualizacao).

import 'package:cloud_firestore/cloud_firestore.dart';

/// Horas sem atividade para marcar [potencialmenteAbandonado] (heurística conservadora).
const int kPrePedidoHorasAbandonoPotencial = 72;

enum PrePedidoFilaOperacional {
  /// Pendente, não substituído, dentro do limiar de tempo — prioridade na fila.
  filaAtiva,

  /// Pendente, não substituído, última atividade há mais de [kPrePedidoHorasAbandonoPotencial] h.
  potencialmenteAbandonado,

  /// `governancaStatus == substituido` (nova tentativa de checkout na mesma sessão).
  substituidoGovernanca,

  /// Confirmado, cancelado, pago, logística, etc. — fora da fila de atendimento imediato.
  historicoEncerrado,
}

bool isGovernancaSubstituidoPrePedido(Map<String, dynamic> p) {
  return (p['governancaStatus'] ?? '').toString().trim() == 'substituido';
}

DateTime? _toDate(dynamic value) {
  if (value == null) return null;
  try {
    if (value is Timestamp) return value.toDate();
    final d = (value as dynamic).toDate();
    if (d is DateTime) return d;
  } catch (_) {}
  return null;
}

/// Última atividade conhecida: o mais recente entre criação e atualização (quando existir).
DateTime? referenciaAtividadePrePedido(Map<String, dynamic> p) {
  final c = _toDate(p['dataCriacao']);
  final a = _toDate(p['dataAtualizacao']);
  if (c == null) return a;
  if (a == null) return c;
  return c.isAfter(a) ? c : a;
}

bool _isStatusHistoricoEncerrado(String st) {
  const encerrados = <String>{
    'confirmado',
    'paid',
    'pago',
    'embalando',
    'enviado',
    'entregue',
    'cancelado',
  };
  return encerrados.contains(st);
}

/// Classificação não destrutiva para ordenação, badges e destaques no painel.
PrePedidoFilaOperacional classificarPrePedidoOperacional(
  Map<String, dynamic> p, {
  DateTime? agora,
}) {
  final now = agora ?? DateTime.now();

  if (isGovernancaSubstituidoPrePedido(p)) {
    return PrePedidoFilaOperacional.substituidoGovernanca;
  }

  final st = (p['status'] ?? 'pendente').toString().toLowerCase().trim();
  if (_isStatusHistoricoEncerrado(st)) {
    return PrePedidoFilaOperacional.historicoEncerrado;
  }

  if (st != 'pendente') {
    // Status desconhecido: não força fila ativa (evita ruído).
    return PrePedidoFilaOperacional.historicoEncerrado;
  }

  final ref = referenciaAtividadePrePedido(p);
  if (ref != null &&
      now.difference(ref) > Duration(hours: kPrePedidoHorasAbandonoPotencial)) {
    return PrePedidoFilaOperacional.potencialmenteAbandonado;
  }

  return PrePedidoFilaOperacional.filaAtiva;
}

/// Contadores para badges e linha de resumo no painel.
class PrePedidoOperacionalStats {
  const PrePedidoOperacionalStats({
    required this.filaAtiva,
    required this.substituidos,
    required this.abandonadosPotencial,
    required this.historicoEncerrado,
    required this.total,
  });

  final int filaAtiva;
  final int substituidos;
  final int abandonadosPotencial;
  final int historicoEncerrado;
  final int total;

  factory PrePedidoOperacionalStats.fromLista(List<Map<String, dynamic>> lista) {
    var fila = 0;
    var subst = 0;
    var aband = 0;
    var hist = 0;
    for (final p in lista) {
      switch (classificarPrePedidoOperacional(p)) {
        case PrePedidoFilaOperacional.filaAtiva:
          fila++;
          break;
        case PrePedidoFilaOperacional.substituidoGovernanca:
          subst++;
          break;
        case PrePedidoFilaOperacional.potencialmenteAbandonado:
          aband++;
          break;
        case PrePedidoFilaOperacional.historicoEncerrado:
          hist++;
          break;
      }
    }
    return PrePedidoOperacionalStats(
      filaAtiva: fila,
      substituidos: subst,
      abandonadosPotencial: aband,
      historicoEncerrado: hist,
      total: lista.length,
    );
  }
}
