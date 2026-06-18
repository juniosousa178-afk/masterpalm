// Sincroniza baixas de contas a receber a partir de lançamentos financeiros remotos
// e estorna saldo local ao excluir lançamento vinculado.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/conta_receber_identity.dart';
import '../core/conta_receber_lancamento_vinculo.dart';
import '../core/financeiro_lancamento_legacy_resolver.dart';
import '../core/safe_cast.dart';
import '../financeiro/financeiro_constants.dart';
import '../models/conta_receber.dart';
import '../models/lancamento_financeiro.dart';
import 'conta_receber_firestore_service.dart';
import 'conta_receber_recebimento_caixa_service.dart';
import 'conta_receber_service.dart';
import 'financeiro_firestore_service.dart';
import 'financeiro_hive_store.dart';

class ContaReceberReconciliacaoResultado {
  final int baixasAplicadas;
  final int baixasJaPresentes;
  final int lancamentosIgnorados;

  const ContaReceberReconciliacaoResultado({
    this.baixasAplicadas = 0,
    this.baixasJaPresentes = 0,
    this.lancamentosIgnorados = 0,
  });
}

class ContaReceberEstornoResultado {
  final bool sucesso;
  final bool contaAtualizada;
  final bool jaEstavaEstornada;
  final String? mensagem;

  const ContaReceberEstornoResultado({
    required this.sucesso,
    this.contaAtualizada = false,
    this.jaEstavaEstornada = false,
    this.mensagem,
  });
}

abstract final class ContaReceberFinanceiroSyncService {
  ContaReceberFinanceiroSyncService._();

  static bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _historicoContemRecebimento({
    required ContaReceber conta,
    required double valor,
    required DateTime data,
  }) {
    for (final h in conta.historicoPagamentos()) {
      final v = (h['valor'] as num?)?.toDouble() ?? 0;
      if (!ContaReceberRecebimentoCaixaService.valoresParecidosRecebimento(
        v,
        valor,
      )) {
        continue;
      }
      final raw = h['data']?.toString() ?? '';
      final dt = DateTime.tryParse(raw);
      if (dt != null && _mesmoDia(dt, data)) return true;
    }
    return false;
  }

  static ContaReceber? resolverContaLocal({
    required Iterable<ContaReceber> contas,
    required String lojaId,
    required ContaReceberRecebimentoRefParsed ref,
  }) =>
      _resolverConta(contas: contas, lojaId: lojaId, ref: ref);

  /// Resolve conta para estorno (referência estruturada ou heurística legada).
  static ContaReceber? resolverContaParaEstorno({
    required Iterable<ContaReceber> contas,
    required String lojaId,
    required LancamentoFinanceiro lancamento,
  }) {
    final ref = recebimentoRefFromLancamento(lancamento);
    if (ref != null) {
      final porRef = _resolverConta(contas: contas, lojaId: lojaId, ref: ref);
      if (porRef != null) return porRef;
    }
    return FinanceiroLancamentoLegacyResolver.resolverContaHeuristica(
      contas: contas,
      lojaId: lojaId,
      l: lancamento,
    );
  }

  static ContaReceber? _resolverConta({
    required Iterable<ContaReceber> contas,
    required String lojaId,
    required ContaReceberRecebimentoRefParsed ref,
  }) {
    if (ref.isFirestoreDocBaixa) {
      for (final c in contas) {
        if (!ContaReceberService.contaPertenceALoja(c, lojaId)) continue;
        if ((c.idFirebase ?? '').trim() == ref.contaReceberDocId) return c;
        if (resolveContaReceberDocId(c) == ref.contaReceberDocId) return c;
      }
      return null;
    }
    if (ref.isStable) {
      for (final c in contas) {
        if (!ContaReceberService.contaPertenceALoja(c, lojaId)) continue;
        if (contaReceberStableId(c) == ref.stableId) return c;
      }
      return null;
    }
    final hk = ref.hiveKey;
    if (hk == null) return null;
    for (final c in contas) {
      if (!ContaReceberService.contaPertenceALoja(c, lojaId)) continue;
      if (hiveKeyOrNull(c.key) == hk) return c;
    }
    return null;
  }

  static DateTime? _dataFromRefDia(String dia, LancamentoFinanceiro l) {
    if (dia.length == 8) {
      final y = int.tryParse(dia.substring(0, 4));
      final m = int.tryParse(dia.substring(4, 6));
      final d = int.tryParse(dia.substring(6, 8));
      if (y != null && m != null && d != null) {
        return DateTime(y, m, d);
      }
    }
    return l.dataPagamento ?? l.dataLancamento;
  }

  /// Pull financeiro remoto e aplica baixas faltantes nas contas locais.
  static Future<ContaReceberReconciliacaoResultado> reconciliarBaixasRemotas({
    required String lojaId,
    bool puxarFirestore = true,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) {
      return const ContaReceberReconciliacaoResultado();
    }

    if (puxarFirestore) {
      try {
        await FinanceiroFirestoreService.pullLojaFirestoreParaHiveFase2d(loja);
      } catch (e) {
        debugPrint(
          '[CR-SYNC] Pull financeiro falhou (type=${e.runtimeType})',
        );
      }
    }

    final finBox = await FinanceiroHiveStore.openLancamentosBox(loja);
    if (finBox == null) {
      return const ContaReceberReconciliacaoResultado();
    }

    final crBox = await ContaReceberService.openBoxLoja(loja);
    var aplicadas = 0;
    var jaPresentes = 0;
    var ignorados = 0;

    for (final l in finBox.values) {
      if (l.lojaId.trim() != loja) continue;
      if (l.status != FinanceiroStatusLancamento.pago) continue;
      if (!lancamentoVinculadoAContaReceber(l)) continue;

      final ref = recebimentoRefFromLancamento(l);
      if (ref == null) {
        ignorados++;
        continue;
      }

      final conta = _resolverConta(
        contas: crBox.values,
        lojaId: loja,
        ref: ref,
      );
      if (conta == null) {
        ignorados++;
        continue;
      }

      final quando = _dataFromRefDia(ref.dia, l) ?? l.dataLancamento;
      if (_historicoContemRecebimento(
        conta: conta,
        valor: l.valor,
        data: quando,
      )) {
        jaPresentes++;
        continue;
      }

      try {
        ContaReceberService.aplicarBaixaNaConta(
          conta: conta,
          valorRecebido: l.valor,
          formaPagamento: l.formaPagamento,
          dataRecebimento: quando,
        );
        await conta.save();
        aplicadas++;
      } catch (e) {
        debugPrint(
          '[CR-SYNC] Falha ao aplicar baixa remota (type=${e.runtimeType})',
        );
        ignorados++;
      }
    }

    if (aplicadas > 0) {
      debugPrint(
        '[CR-SYNC] Reconciliação loja=$loja aplicadas=$aplicadas '
        'jaPresentes=$jaPresentes ignorados=$ignorados',
      );
    }

    return ContaReceberReconciliacaoResultado(
      baixasAplicadas: aplicadas,
      baixasJaPresentes: jaPresentes,
      lancamentosIgnorados: ignorados,
    );
  }

  /// Reverte saldo da conta ao excluir lançamento de recebimento fiado.
  static Future<ContaReceberEstornoResultado> reverterBaixaPorLancamento({
    required String lojaId,
    required LancamentoFinanceiro lancamento,
    bool permitirResolucaoLegada = false,
  }) async {
    final loja = lojaId.trim();
    final pareceCr = lancamentoVinculadoAContaReceber(lancamento) ||
        (permitirResolucaoLegada &&
            FinanceiroLancamentoLegacyResolver.pareceBaixaContaReceber(
              lancamento,
            ));
    if (loja.isEmpty || !pareceCr) {
      return const ContaReceberEstornoResultado(
        sucesso: false,
        mensagem: 'Lançamento não vinculado a conta a receber.',
      );
    }

    final crBox = await ContaReceberService.openBoxLoja(loja);
    final conta = resolverContaParaEstorno(
      contas: crBox.values,
      lojaId: loja,
      lancamento: lancamento,
    );

    var ref = recebimentoRefFromLancamento(lancamento);
    if (conta == null) {
      return ContaReceberEstornoResultado(
        sucesso: false,
        mensagem: permitirResolucaoLegada
            ? FinanceiroLancamentoLegacyResolver.msgEstornoLegadoSemVinculo
            : 'Conta local não encontrada.',
        contaAtualizada: false,
      );
    }

    final quando = ref != null
        ? (_dataFromRefDia(ref.dia, lancamento) ?? lancamento.dataLancamento)
        : (lancamento.dataPagamento ?? lancamento.dataLancamento);
    if (!_historicoContemRecebimento(
      conta: conta,
      valor: lancamento.valor,
      data: quando,
    )) {
      return const ContaReceberEstornoResultado(
        sucesso: true,
        jaEstavaEstornada: true,
        contaAtualizada: false,
        mensagem: 'Baixa já estava ausente na conta local.',
      );
    }

    conta.normalizarCamposFinanceiros();
    final hist = conta.historicoPagamentos();
    hist.removeWhere((h) {
      final v = (h['valor'] as num?)?.toDouble() ?? 0;
      if (!ContaReceberRecebimentoCaixaService.valoresParecidosRecebimento(
        v,
        lancamento.valor,
      )) {
        return false;
      }
      final raw = h['data']?.toString() ?? '';
      final dt = DateTime.tryParse(raw);
      return dt != null && _mesmoDia(dt, quando);
    });
    conta.historicoPagamentosJson = jsonEncode(hist);

    conta.valorPago =
        (conta.valorPago - lancamento.valor).clamp(0.0, double.infinity);
    conta.valor = conta.valor + lancamento.valor;
    if (conta.valorOriginal + 1e-9 < conta.valorPago + conta.valor) {
      conta.valorOriginal = conta.valorPago + conta.valor;
    }
    conta.pago = false;
    conta.recalcularStatus();
    await conta.save();

    final docId = (conta.idFirebase ?? '').trim();
    if (docId.isNotEmpty) {
      var bx = ref?.baixaId.trim() ?? '';
      if (bx.isEmpty) {
        bx = baixaIdDeterministico(
          contaReceberId: docId,
          valor: lancamento.valor,
          dataRecebimento: quando,
          formaPagamento: lancamento.formaPagamento,
        );
      }
      if (bx.isNotEmpty) {
        await ContaReceberFirestoreService.estornarBaixaRemota(
          lojaId: loja,
          contaReceberDocId: docId,
          baixaId: bx,
        );
        await ContaReceberFirestoreService.pullContasReceberRemotas(loja);
      } else {
        await ContaReceberFirestoreService.upsertContaReceber(
          conta,
          lastWriteOrigin: 'estorno_local',
        );
      }
    }

    return const ContaReceberEstornoResultado(
      sucesso: true,
      contaAtualizada: true,
    );
  }
}
