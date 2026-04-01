// lib/services/financeiro_firestore_service.dart
// Escrita remota complementar ao Hive (Fase 2A/2B). Sem pull; falhas não bloqueiam o app.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/gasto_fixo_mensal.dart';
import '../models/lancamento_financeiro.dart';
import 'financeiro_hive_store.dart';

/// Resultado da migração Fase 2C (Política A: só cria se doc remoto não existir).
class FinanceiroMigracaoF2cResultado {
  final int lancamentosEnviados;
  final int lancamentosPulados;
  final int lancamentosErros;
  final int gastosEnviados;
  final int gastosPulados;
  final int gastosErros;

  const FinanceiroMigracaoF2cResultado({
    this.lancamentosEnviados = 0,
    this.lancamentosPulados = 0,
    this.lancamentosErros = 0,
    this.gastosEnviados = 0,
    this.gastosPulados = 0,
    this.gastosErros = 0,
  });

  int get totalEnviados => lancamentosEnviados + gastosEnviados;
  int get totalPulados => lancamentosPulados + gastosPulados;
  int get totalErros => lancamentosErros + gastosErros;
}

/// Serviço de escrita Firestore para o módulo financeiro.
/// Todos os métodos são defensivos: erros são logados e não propagados.
class FinanceiroFirestoreService {
  FinanceiroFirestoreService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Chave na box `config` — informativa, não bloqueia reexecução.
  static String chaveRegistroMigracaoF2c(String lojaId) =>
      'financeiro_migr_f2c_${lojaId.trim()}';

  static DocumentReference<Map<String, dynamic>> _refLancamento(
    String lojaId,
    String id,
  ) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection('lancamentos_financeiros')
        .doc(id);
  }

  static DocumentReference<Map<String, dynamic>> _refGastoFixo(
    String lojaId,
    String id,
  ) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection('gastos_fixos_mensais')
        .doc(id);
  }

  static Map<String, dynamic> _mapLancamento(LancamentoFinanceiro l) {
    return {
      'lojaId': l.lojaId,
      'descricao': l.descricao,
      'valor': l.valor,
      'tipo': l.tipo,
      'categoria': l.categoria,
      'subcategoria': l.subcategoria,
      'status': l.status,
      'formaPagamento': l.formaPagamento,
      'fornecedor': l.fornecedor,
      'observacao': l.observacao,
      'dataLancamento': Timestamp.fromDate(l.dataLancamento),
      'competenciaMes': l.competenciaMes,
      'competenciaAno': l.competenciaAno,
      'recorrente': l.recorrente,
      'origem': l.origem,
      'usuarioId': l.usuarioId,
      'usuarioNome': l.usuarioNome,
      'centroCusto': l.centroCusto,
      'anexoComprovante': l.anexoComprovante,
      'dataPagamento': l.dataPagamento != null
          ? Timestamp.fromDate(l.dataPagamento!)
          : FieldValue.delete(),
    };
  }

  static Map<String, dynamic> _mapGastoFixo(GastoFixoMensal g) {
    return {
      'lojaId': g.lojaId,
      'descricao': g.descricao,
      'valorPadrao': g.valorPadrao,
      'categoria': g.categoria,
      'subcategoria': g.subcategoria,
      'diaVencimento': g.diaVencimento,
      'ativo': g.ativo,
      'formaPagamentoPadrao': g.formaPagamentoPadrao,
      'fornecedor': g.fornecedor,
      'observacao': g.observacao,
      'centroCusto': g.centroCusto,
    };
  }

  /// Grava ou atualiza lançamento (merge). Hive já deve estar persistido.
  static Future<void> upsertLancamento(LancamentoFinanceiro l) async {
    try {
      final data = _mapLancamento(l);
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _refLancamento(l.lojaId, l.id).set(
        data,
        SetOptions(merge: true),
      );
      debugPrint(
        '[FINANCEIRO-FS] Lancamento ${l.id} upsert ok (loja=${l.lojaId})',
      );
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro upsert lancamento (type=${e.runtimeType})',
      );
    }
  }

  /// Remove documento remoto (espelha exclusão local). Hard delete — sem soft delete no Firestore.
  static Future<void> deleteLancamento({
    required String lojaId,
    required String id,
  }) async {
    try {
      await _refLancamento(lojaId, id).delete();
      debugPrint('[FINANCEIRO-FS] Lancamento $id delete ok (loja=$lojaId)');
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro delete lancamento (type=${e.runtimeType})',
      );
    }
  }

  static Future<void> upsertGastoFixo(GastoFixoMensal g) async {
    try {
      final data = _mapGastoFixo(g);
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _refGastoFixo(g.lojaId, g.id).set(
        data,
        SetOptions(merge: true),
      );
      debugPrint(
        '[FINANCEIRO-FS] Gasto fixo ${g.id} upsert ok (loja=${g.lojaId})',
      );
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro upsert gasto fixo (type=${e.runtimeType})',
      );
    }
  }

  static Future<void> deleteGastoFixo({
    required String lojaId,
    required String id,
  }) async {
    try {
      await _refGastoFixo(lojaId, id).delete();
      debugPrint('[FINANCEIRO-FS] Gasto fixo $id delete ok (loja=$lojaId)');
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro delete gasto fixo (type=${e.runtimeType})',
      );
    }
  }

  /// Migração Hive → Firestore, **Política A**: `get` antes; só `set` se não existir.
  /// Hive não é alterado. Continua mesmo com erros parciais.
  static Future<FinanceiroMigracaoF2cResultado> migrarLojaHiveParaFirestorePolicyA(
    String lojaId,
  ) async {
    final id = lojaId.trim();
    if (id.isEmpty) {
      return const FinanceiroMigracaoF2cResultado();
    }

    var le = 0, lp = 0, lx = 0;
    var ge = 0, gp = 0, gx = 0;

    final lBox = await FinanceiroHiveStore.openLancamentosBox(id);
    if (lBox != null) {
      for (final l in lBox.values) {
        if (l.lojaId != id) continue;
        try {
          final ref = _refLancamento(id, l.id);
          final snap = await ref.get();
          if (snap.exists) {
            lp++;
            continue;
          }
          final data = _mapLancamento(l);
          data['updatedAt'] = FieldValue.serverTimestamp();
          await ref.set(data, SetOptions(merge: true));
          le++;
        } catch (e) {
          lx++;
          debugPrint(
            '[FINANCEIRO-FS] Migração lancamento ${l.id} (type=${e.runtimeType})',
          );
        }
      }
    }

    final gBox = await FinanceiroHiveStore.openGastosFixosBox(id);
    if (gBox != null) {
      for (final g in gBox.values) {
        if (g.lojaId != id) continue;
        try {
          final ref = _refGastoFixo(id, g.id);
          final snap = await ref.get();
          if (snap.exists) {
            gp++;
            continue;
          }
          final data = _mapGastoFixo(g);
          data['updatedAt'] = FieldValue.serverTimestamp();
          await ref.set(data, SetOptions(merge: true));
          ge++;
        } catch (e) {
          gx++;
          debugPrint(
            '[FINANCEIRO-FS] Migração gasto fixo ${g.id} (type=${e.runtimeType})',
          );
        }
      }
    }

    final resultado = FinanceiroMigracaoF2cResultado(
      lancamentosEnviados: le,
      lancamentosPulados: lp,
      lancamentosErros: lx,
      gastosEnviados: ge,
      gastosPulados: gp,
      gastosErros: gx,
    );
    await registrarUltimaMigracaoF2c(lojaId: id, resultado: resultado);
    return resultado;
  }

  /// Grava resumo na box `config` (informativo).
  static Future<void> registrarUltimaMigracaoF2c({
    required String lojaId,
    required FinanceiroMigracaoF2cResultado resultado,
  }) async {
    try {
      final box = Hive.isBoxOpen('config')
          ? Hive.box('config')
          : await Hive.openBox('config');
      await box.put(chaveRegistroMigracaoF2c(lojaId), {
        'executadoEm': DateTime.now().toIso8601String(),
        'lancamentosEnviados': resultado.lancamentosEnviados,
        'lancamentosPulados': resultado.lancamentosPulados,
        'lancamentosErros': resultado.lancamentosErros,
        'gastosEnviados': resultado.gastosEnviados,
        'gastosPulados': resultado.gastosPulados,
        'gastosErros': resultado.gastosErros,
      });
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro ao registrar migração F2c (type=${e.runtimeType})',
      );
    }
  }

  /// Lê último registro salvo em `config`, ou `null`.
  static Future<FinanceiroMigracaoF2cRegistroLeitura?> lerUltimaMigracaoF2c(
    String lojaId,
  ) async {
    try {
      final box = Hive.isBoxOpen('config')
          ? Hive.box('config')
          : await Hive.openBox('config');
      final raw = box.get(chaveRegistroMigracaoF2c(lojaId));
      if (raw is! Map) return null;
      final m = Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
      return FinanceiroMigracaoF2cRegistroLeitura.fromMap(m);
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro ler registro migração (type=${e.runtimeType})',
      );
      return null;
    }
  }
}

/// Leitura do mapa persistido em `config` (UI).
class FinanceiroMigracaoF2cRegistroLeitura {
  final String? executadoEmIso;
  final int lancamentosEnviados;
  final int lancamentosPulados;
  final int lancamentosErros;
  final int gastosEnviados;
  final int gastosPulados;
  final int gastosErros;

  FinanceiroMigracaoF2cRegistroLeitura({
    this.executadoEmIso,
    this.lancamentosEnviados = 0,
    this.lancamentosPulados = 0,
    this.lancamentosErros = 0,
    this.gastosEnviados = 0,
    this.gastosPulados = 0,
    this.gastosErros = 0,
  });

  factory FinanceiroMigracaoF2cRegistroLeitura.fromMap(Map<String, dynamic> m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return FinanceiroMigracaoF2cRegistroLeitura(
      executadoEmIso: m['executadoEm']?.toString(),
      lancamentosEnviados: n('lancamentosEnviados'),
      lancamentosPulados: n('lancamentosPulados'),
      lancamentosErros: n('lancamentosErros'),
      gastosEnviados: n('gastosEnviados'),
      gastosPulados: n('gastosPulados'),
      gastosErros: n('gastosErros'),
    );
  }
}
