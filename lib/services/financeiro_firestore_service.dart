// lib/services/financeiro_firestore_service.dart
// Escrita remota complementar ao Hive (Fase 2A/2B) + pull conservador Fase 2D.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../financeiro/financeiro_constants.dart';
import '../core/financeiro_lancamento_duplicidade_resolver.dart';
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

/// Resultado do pull Fase 2D (Firestore → Hive: só `put` se chave ausente).
class FinanceiroPullF2dResultado {
  final int lancamentosImportados;
  final int lancamentosPulados;
  final int lancamentosErros;
  final int gastosImportados;
  final int gastosPulados;
  final int gastosErros;
  final bool ignoradoJaEmExecucao;

  const FinanceiroPullF2dResultado({
    this.lancamentosImportados = 0,
    this.lancamentosPulados = 0,
    this.lancamentosErros = 0,
    this.gastosImportados = 0,
    this.gastosPulados = 0,
    this.gastosErros = 0,
    this.ignoradoJaEmExecucao = false,
  });

  int get totalImportados => lancamentosImportados + gastosImportados;
  int get totalPulados => lancamentosPulados + gastosPulados;
  int get totalErros => lancamentosErros + gastosErros;
}

/// Serviço de escrita Firestore para o módulo financeiro.
/// Todos os métodos são defensivos: erros são logados e não propagados.
class FinanceiroFirestoreService {
  FinanceiroFirestoreService._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  /// Evita dois pulls simultâneos (mesmo isolado).
  static bool _pullF2dEmExecucao = false;

  /// Chave na box `config` — informativa, não bloqueia reexecução.
  static String chaveRegistroMigracaoF2c(String lojaId) =>
      'financeiro_migr_f2c_${lojaId.trim()}';

  /// Último pull Firestore → Hive por loja (informativo).
  static String chaveRegistroPullF2d(String lojaId) =>
      'financeiro_pull_f2d_${lojaId.trim()}';

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
      'referenciaExterna': l.referenciaExterna,
      'solicitarAtualizacaoEstoque': l.solicitarAtualizacaoEstoque,
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

  static DateTime? _fsDateTime(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static double? _fsDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return null;
  }

  static int _fsInt(dynamic v, int fallback) {
    if (v is num) return v.toInt();
    return fallback;
  }

  static bool _fsBool(dynamic v, bool fallback) {
    if (v is bool) return v;
    return fallback;
  }

  static String _fsString(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    return v.toString();
  }

  static String _fsStatusLancamento(dynamic v) {
    final s = v?.toString();
    if (s == FinanceiroStatusLancamento.pendente) {
      return FinanceiroStatusLancamento.pendente;
    }
    return FinanceiroStatusLancamento.pago;
  }

  /// Monta modelo a partir do mapa Firestore; `docId` é a fonte do id local.
  static LancamentoFinanceiro? _lancamentoFromFirestore(
    String docId,
    Map<String, dynamic> data,
    String lojaIdEsperada,
  ) {
    try {
      final valor = _fsDouble(data['valor']);
      if (valor == null) return null;
      final dataLancamento = _fsDateTime(data['dataLancamento']);
      if (dataLancamento == null) return null;
      final lojaDoc = _fsString(data['lojaId']).trim();
      if (lojaDoc.isNotEmpty && lojaDoc != lojaIdEsperada) {
        return null;
      }
      final dpRaw = data['dataPagamento'];
      DateTime? dataPagamento;
      if (dpRaw != null) {
        dataPagamento = _fsDateTime(dpRaw);
      }
      final cm = _fsInt(data['competenciaMes'], dataLancamento.month);
      final ca = _fsInt(data['competenciaAno'], dataLancamento.year);
      return LancamentoFinanceiro(
        id: docId,
        lojaId: lojaIdEsperada,
        descricao: _fsString(data['descricao']),
        valor: valor,
        tipo: FinanceiroTipoLancamento.tipoOuPadrao(
          _fsString(data['tipo'], FinanceiroTipoLancamento.despesaOperacional),
        ),
        categoria: financeiroCategoriaOuPadrao(_fsString(data['categoria'])),
        subcategoria: _fsString(data['subcategoria']),
        status: _fsStatusLancamento(data['status']),
        formaPagamento: _fsString(data['formaPagamento']),
        fornecedor: _fsString(data['fornecedor']),
        observacao: _fsString(data['observacao']),
        dataLancamento: dataLancamento,
        dataPagamento: dataPagamento,
        competenciaMes: cm,
        competenciaAno: ca,
        recorrente: _fsBool(data['recorrente'], false),
        origem: _fsString(data['origem'], FinanceiroOrigemLancamento.manual),
        usuarioId: _fsString(data['usuarioId']),
        usuarioNome: _fsString(data['usuarioNome']),
        centroCusto: _fsString(data['centroCusto']),
        anexoComprovante: _fsString(data['anexoComprovante']),
        referenciaExterna: _fsString(data['referenciaExterna']),
        solicitarAtualizacaoEstoque:
            _fsBool(data['solicitarAtualizacaoEstoque'], false),
      );
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Parse lancamento remoto $docId (type=${e.runtimeType})',
      );
      return null;
    }
  }

  static GastoFixoMensal? _gastoFixoFromFirestore(
    String docId,
    Map<String, dynamic> data,
    String lojaIdEsperada,
  ) {
    try {
      final lojaDoc = _fsString(data['lojaId']).trim();
      if (lojaDoc.isNotEmpty && lojaDoc != lojaIdEsperada) {
        return null;
      }
      final dia = _fsInt(data['diaVencimento'], 1).clamp(1, 31);
      return GastoFixoMensal(
        id: docId,
        lojaId: lojaIdEsperada,
        descricao: _fsString(data['descricao']),
        valorPadrao: _fsDouble(data['valorPadrao']) ?? 0,
        categoria: financeiroCategoriaOuPadrao(_fsString(data['categoria'])),
        subcategoria: _fsString(data['subcategoria']),
        diaVencimento: dia,
        ativo: _fsBool(data['ativo'], true),
        formaPagamentoPadrao: _fsString(data['formaPagamentoPadrao']),
        fornecedor: _fsString(data['fornecedor']),
        observacao: _fsString(data['observacao']),
        centroCusto: _fsString(data['centroCusto']),
      );
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Parse gasto fixo remoto $docId (type=${e.runtimeType})',
      );
      return null;
    }
  }

  /// Grava ou atualiza lançamento (merge). Hive já deve estar persistido.
  /// Retorna `true` se o remoto foi gravado com sucesso.
  static bool _lancamentoRemotoExcluidoOuEstornado(Map<String, dynamic> data) {
    if (data['deletedAt'] != null) return true;
    if (_fsBool(data['estornado'], false)) return true;
    final st = _fsString(data['status']);
    return st == 'excluido' || st == 'estornado';
  }

  static Future<bool> upsertLancamento(LancamentoFinanceiro l) async {
    try {
      final data = _mapLancamento(l);
      data['updatedAt'] = FieldValue.serverTimestamp();
      data['deletedAt'] = FieldValue.delete();
      data['estornado'] = false;
      data['deletedBy'] = FieldValue.delete();
      data['motivoExclusao'] = FieldValue.delete();
      data['estornadoEm'] = FieldValue.delete();
      data['estornadoPor'] = FieldValue.delete();
      data['motivoEstorno'] = FieldValue.delete();
      data['valorEstornado'] = FieldValue.delete();
      await _refLancamento(l.lojaId, l.id).set(
        data,
        SetOptions(merge: true),
      );
      debugPrint(
        '[FINANCEIRO-FS] Lancamento ${l.id} upsert ok (loja=${l.lojaId})',
      );
      return true;
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro upsert lancamento (type=${e.runtimeType})',
      );
      return false;
    }
  }

  static Future<bool> editarLancamentoManual({
    required LancamentoFinanceiro l,
    String editadoPor = '',
    String motivoEdicao = '',
    Map<String, dynamic> dadosAnteriores = const {},
  }) async {
    try {
      final data = _mapLancamento(l);
      data['updatedAt'] = FieldValue.serverTimestamp();
      data['editadoEm'] = FieldValue.serverTimestamp();
      data['editadoPor'] = editadoPor;
      data['motivoEdicao'] = motivoEdicao;
      data['dadosAnteriores'] = dadosAnteriores;
      await _refLancamento(l.lojaId, l.id).set(
        data,
        SetOptions(merge: true),
      );
      debugPrint('[FINANCEIRO-FS] Lancamento ${l.id} editado (loja=${l.lojaId})');
      return true;
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro editar lancamento (type=${e.runtimeType})',
      );
      return false;
    }
  }

  /// Soft delete manual com auditoria (mantém documento para rastreio cross-device).
  static Future<bool> softDeleteLancamentoManual({
    required String lojaId,
    required String id,
    String deletedBy = '',
    String motivoExclusao = '',
    String origem = '',
    String referenciaExterna = '',
  }) async {
    try {
      await _refLancamento(lojaId, id).set(
        {
          'deletedAt': FieldValue.serverTimestamp(),
          'deletedBy': deletedBy,
          'motivoExclusao': motivoExclusao,
          'origem': origem,
          'referenciaExterna': referenciaExterna,
          'status': 'excluido',
          'estornado': false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('[FINANCEIRO-FS] Lancamento $id soft-delete manual (loja=$lojaId)');
      return true;
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro soft-delete manual (type=${e.runtimeType})',
      );
      return false;
    }
  }

  /// Soft delete por estorno de baixa de Conta a Receber.
  static Future<bool> softDeleteLancamentoEstorno({
    required String lojaId,
    required String id,
    String estornadoPor = '',
    String motivoEstorno = '',
    String origem = '',
    String referenciaExterna = '',
    String contaReceberId = '',
    String vendaIdFirebase = '',
    double valorEstornado = 0,
  }) async {
    try {
      await _refLancamento(lojaId, id).set(
        {
          'deletedAt': FieldValue.serverTimestamp(),
          'estornado': true,
          'estornadoEm': FieldValue.serverTimestamp(),
          'estornadoPor': estornadoPor,
          'motivoEstorno': motivoEstorno,
          'origem': origem,
          'referenciaExterna': referenciaExterna,
          'contaReceberId': contaReceberId,
          'vendaIdFirebase': vendaIdFirebase,
          'valorEstornado': valorEstornado,
          'status': 'estornado',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('[FINANCEIRO-FS] Lancamento $id estornado (loja=$lojaId)');
      return true;
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro soft-delete estorno (type=${e.runtimeType})',
      );
      return false;
    }
  }

  /// Remove documento remoto — preferir [softDeleteLancamentoManual] / estorno.
  static Future<bool> deleteLancamento({
    required String lojaId,
    required String id,
  }) async {
    return softDeleteLancamentoManual(lojaId: lojaId, id: id);
  }

  /// Aplica tombstones remotos no Hive (estorno/exclusão em outro dispositivo).
  static Future<int> sincronizarTombstonesLancamentos(String lojaId) async {
    final id = lojaId.trim();
    if (id.isEmpty) return 0;
    var removidos = 0;
    try {
      final lBox = await FinanceiroHiveStore.openLancamentosBox(id);
      if (lBox == null) return 0;
      final qs = await _db
          .collection('lojas')
          .doc(id)
          .collection('lancamentos_financeiros')
          .where('lojaId', isEqualTo: id)
          .get();
      for (final doc in qs.docs) {
        final data = doc.data();
        if (!_lancamentoRemotoExcluidoOuEstornado(data)) continue;
        if (lBox.containsKey(doc.id)) {
          await lBox.delete(doc.id);
          removidos++;
        }
      }
      if (removidos > 0) {
        debugPrint(
          '[FINANCEIRO-FS] Tombstones aplicados loja=$id removidos=$removidos',
        );
      }
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro tombstones lancamentos (type=${e.runtimeType})',
      );
    }
    return removidos;
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

  /// Pull Firestore → Hive (Fase 2D): só `box.put` se `!containsKey(docId)`.
  /// Não apaga nem substitui chaves existentes. Uma execução por vez.
  static Future<FinanceiroPullF2dResultado> pullLojaFirestoreParaHiveFase2d(
    String lojaId,
  ) async {
    final id = lojaId.trim();
    if (id.isEmpty) {
      return const FinanceiroPullF2dResultado();
    }
    if (_pullF2dEmExecucao) {
      return const FinanceiroPullF2dResultado(ignoradoJaEmExecucao: true);
    }
    _pullF2dEmExecucao = true;

    var li = 0, lp = 0, lx = 0;
    var gi = 0, gp = 0, gx = 0;

    try {
      final lBox = await FinanceiroHiveStore.openLancamentosBox(id);
      if (lBox != null) {
        try {
          final qs = await _db
              .collection('lojas')
              .doc(id)
              .collection('lancamentos_financeiros')
              .where('lojaId', isEqualTo: id)
              .get();
          for (final doc in qs.docs) {
            try {
              final data = doc.data();
              if (_lancamentoRemotoExcluidoOuEstornado(data)) {
                if (lBox.containsKey(doc.id)) {
                  await lBox.delete(doc.id);
                  li++;
                }
                continue;
              }
              if (lBox.containsKey(doc.id)) {
                lp++;
                continue;
              }
              final model = _lancamentoFromFirestore(doc.id, data, id);
              if (model == null) {
                lx++;
                continue;
              }
              final dupLocal =
                  FinanceiroLancamentoDuplicidadeResolver.encontrarDuplicataExistente(
                candidato: model,
                lancamentos: lBox.values,
                lojaId: id,
              );
              if (dupLocal != null && dupLocal.id.trim() != model.id.trim()) {
                lp++;
                debugPrint(
                  '[FIN-DUP][ANTI-DUP-BAIXA-CR] pull skip doc=${doc.id} '
                  'mantém local=${dupLocal.id}',
                );
                continue;
              }
              await lBox.put(doc.id, model);
              li++;
            } catch (e) {
              lx++;
              debugPrint(
                '[FINANCEIRO-FS] Pull lancamento ${doc.id} (type=${e.runtimeType})',
              );
            }
          }
        } catch (e) {
          debugPrint(
            '[FINANCEIRO-FS] Pull query lancamentos (type=${e.runtimeType})',
          );
        }
      }

      final gBox = await FinanceiroHiveStore.openGastosFixosBox(id);
      if (gBox != null) {
        try {
          final qs = await _db
              .collection('lojas')
              .doc(id)
              .collection('gastos_fixos_mensais')
              .where('lojaId', isEqualTo: id)
              .get();
          for (final doc in qs.docs) {
            try {
              if (gBox.containsKey(doc.id)) {
                gp++;
                continue;
              }
              final data = doc.data();
              final model = _gastoFixoFromFirestore(doc.id, data, id);
              if (model == null) {
                gx++;
                continue;
              }
              await gBox.put(doc.id, model);
              gi++;
            } catch (e) {
              gx++;
              debugPrint(
                '[FINANCEIRO-FS] Pull gasto fixo ${doc.id} (type=${e.runtimeType})',
              );
            }
          }
        } catch (e) {
          debugPrint(
            '[FINANCEIRO-FS] Pull query gastos_fixos (type=${e.runtimeType})',
          );
        }
      }
    } finally {
      _pullF2dEmExecucao = false;
    }

    final resultado = FinanceiroPullF2dResultado(
      lancamentosImportados: li,
      lancamentosPulados: lp,
      lancamentosErros: lx,
      gastosImportados: gi,
      gastosPulados: gp,
      gastosErros: gx,
    );
    if (!resultado.ignoradoJaEmExecucao) {
      await registrarUltimaPullF2d(lojaId: id, resultado: resultado);
    }
    return resultado;
  }

  static Future<void> registrarUltimaPullF2d({
    required String lojaId,
    required FinanceiroPullF2dResultado resultado,
  }) async {
    if (resultado.ignoradoJaEmExecucao) return;
    try {
      final box = Hive.isBoxOpen('config')
          ? Hive.box('config')
          : await Hive.openBox('config');
      await box.put(chaveRegistroPullF2d(lojaId), {
        'executadoEm': DateTime.now().toIso8601String(),
        'lancamentosImportados': resultado.lancamentosImportados,
        'lancamentosPulados': resultado.lancamentosPulados,
        'lancamentosErros': resultado.lancamentosErros,
        'gastosImportados': resultado.gastosImportados,
        'gastosPulados': resultado.gastosPulados,
        'gastosErros': resultado.gastosErros,
      });
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro registrar pull F2d (type=${e.runtimeType})',
      );
    }
  }

  static Future<FinanceiroPullF2dRegistroLeitura?> lerUltimaPullF2d(
    String lojaId,
  ) async {
    try {
      final box = Hive.isBoxOpen('config')
          ? Hive.box('config')
          : await Hive.openBox('config');
      final raw = box.get(chaveRegistroPullF2d(lojaId));
      if (raw is! Map) return null;
      final m = Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
      return FinanceiroPullF2dRegistroLeitura.fromMap(m);
    } catch (e) {
      debugPrint(
        '[FINANCEIRO-FS] Erro ler pull F2d (type=${e.runtimeType})',
      );
      return null;
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

/// Leitura do registro de último pull (box `config`).
class FinanceiroPullF2dRegistroLeitura {
  final String? executadoEmIso;
  final int lancamentosImportados;
  final int lancamentosPulados;
  final int lancamentosErros;
  final int gastosImportados;
  final int gastosPulados;
  final int gastosErros;

  FinanceiroPullF2dRegistroLeitura({
    this.executadoEmIso,
    this.lancamentosImportados = 0,
    this.lancamentosPulados = 0,
    this.lancamentosErros = 0,
    this.gastosImportados = 0,
    this.gastosPulados = 0,
    this.gastosErros = 0,
  });

  factory FinanceiroPullF2dRegistroLeitura.fromMap(Map<String, dynamic> m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return FinanceiroPullF2dRegistroLeitura(
      executadoEmIso: m['executadoEm']?.toString(),
      lancamentosImportados: n('lancamentosImportados'),
      lancamentosPulados: n('lancamentosPulados'),
      lancamentosErros: n('lancamentosErros'),
      gastosImportados: n('gastosImportados'),
      gastosPulados: n('gastosPulados'),
      gastosErros: n('gastosErros'),
    );
  }
}
