// lib/services/ia_uso_limite_service.dart
// Contador de uso diário da IA por loja. Limites: 25 perguntas, 25 descrição, 25 financeiro.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipos de uso da IA. Cada tipo tem limite diário por loja.
enum TipoUsoIa {
  perguntas, // 25/dia: chat dicas, análise vendas, título, categoria, legenda, etc.
  descricao, // 25/dia: sugestão de descrição de produto
  financeiro, // 25/dia: análise em relatórios financeiros
}

class IaUsoLimiteService {
  IaUsoLimiteService._();

  static const int _limitePerguntas = 25;
  static const int _limiteDescricao = 25;
  static const int _limiteFinanceiro = 25;

  static int limiteDe(TipoUsoIa tipo) {
    switch (tipo) {
      case TipoUsoIa.perguntas:
        return _limitePerguntas;
      case TipoUsoIa.descricao:
        return _limiteDescricao;
      case TipoUsoIa.financeiro:
        return _limiteFinanceiro;
    }
  }

  static String _docIdHoje() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static DocumentReference<Map<String, dynamic>> _docUso(String lojaId) {
    return FirebaseFirestore.instance
        .collection('lojas')
        .doc(lojaId)
        .collection('ia_uso')
        .doc(_docIdHoje());
  }

  /// Verifica se a loja pode usar a IA no tipo informado.
  static Future<bool> canUse(String? lojaId, TipoUsoIa tipo) async {
    if (lojaId == null || lojaId.trim().isEmpty) return true;
    final key = tipo.name;
    final doc = await _docUso(lojaId.trim()).get();
    final data = doc.data() ?? {};
    final atual = (data[key] as num?)?.toInt() ?? 0;
    return atual < limiteDe(tipo);
  }

  /// Retorna o uso atual do dia por tipo.
  static Future<Map<TipoUsoIa, int>> getUsoAtual(String? lojaId) async {
    final result = <TipoUsoIa, int>{
      TipoUsoIa.perguntas: 0,
      TipoUsoIa.descricao: 0,
      TipoUsoIa.financeiro: 0,
    };
    if (lojaId == null || lojaId.trim().isEmpty) return result;
    final doc = await _docUso(lojaId.trim()).get();
    final data = doc.data() ?? {};
    for (final t in TipoUsoIa.values) {
      result[t] = (data[t.name] as num?)?.toInt() ?? 0;
    }
    return result;
  }

  /// Registra um uso após chamada bem-sucedida. Usa transação para evitar race.
  static Future<void> recordUse(String? lojaId, TipoUsoIa tipo) async {
    if (lojaId == null || lojaId.trim().isEmpty) return;
    final ref = _docUso(lojaId.trim());
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = Map<String, dynamic>.from(snap.data() ?? {});
      final key = tipo.name;
      final atual = (data[key] as num?)?.toInt() ?? 0;
      data[key] = atual + 1;
      data['ultima_atualizacao'] = FieldValue.serverTimestamp();
      tx.set(ref, data, SetOptions(merge: true));
    });
  }

  /// Mensagem amigável quando o limite é atingido.
  static String messageLimitExcedido(TipoUsoIa tipo) {
    final lim = limiteDe(tipo);
    final label = switch (tipo) {
      TipoUsoIa.perguntas => 'Perguntas/dicas',
      TipoUsoIa.descricao => 'Sugestões de descrição',
      TipoUsoIa.financeiro => 'Análise financeira',
    };
    return 'Limite diário de $lim $label atingido. Tente novamente amanhã.';
  }
}
