// Edição segura de lançamentos financeiros manuais (não baixa CR / processo automático).

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/financeiro_lancamento_acao.dart';
import '../core/financeiro_lancamento_legacy_resolver.dart';
import '../models/lancamento_financeiro.dart';
import 'financeiro_firestore_service.dart';
import 'financeiro_hive_store.dart';

class FinanceiroLancamentoEdicaoCampos {
  const FinanceiroLancamentoEdicaoCampos({
    required this.descricao,
    required this.valor,
    required this.dataLancamento,
    this.dataPagamento,
    this.categoria = '',
    this.formaPagamento = '',
    this.observacao = '',
  });

  final String descricao;
  final double valor;
  final DateTime dataLancamento;
  final DateTime? dataPagamento;
  final String categoria;
  final String formaPagamento;
  final String observacao;
}

class FinanceiroLancamentoEdicaoResultado {
  const FinanceiroLancamentoEdicaoResultado({
    required this.sucesso,
    this.mensagemErro,
  });

  final bool sucesso;
  final String? mensagemErro;
}

abstract final class FinanceiroLancamentoEdicaoService {
  FinanceiroLancamentoEdicaoService._();

  static bool podeEditar(LancamentoFinanceiro l) =>
      FinanceiroLancamentoAcaoResolver.resolver(l).podeEditar;

  static Future<String> _usuarioAtual() async {
    try {
      final sessao = await Hive.openBox('sessao');
      return (sessao.get('usuario_logado') ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  static Future<FinanceiroLancamentoEdicaoResultado> editarLancamentoManual({
    required String lojaId,
    required LancamentoFinanceiro lancamento,
    required FinanceiroLancamentoEdicaoCampos campos,
    String motivoEdicao = '',
  }) async {
    debugPrint('[FIN-GESTAO][EDITAR-CLICK] id=${lancamento.id} key=${lancamento.key}');

    final acao = FinanceiroLancamentoAcaoResolver.resolver(lancamento);
    if (!acao.podeEditar) {
      return FinanceiroLancamentoEdicaoResultado(
        sucesso: false,
        mensagemErro: acao.motivoBloqueio ??
            FinanceiroLancamentoAcaoResolver.msgVinculoProcesso,
      );
    }

    final lid = lojaId.trim();
    if (lid.isEmpty) {
      return const FinanceiroLancamentoEdicaoResultado(
        sucesso: false,
        mensagemErro: 'Loja inválida.',
      );
    }

    final box = await FinanceiroHiveStore.openLancamentosBox(lid);
    if (box == null) {
      return const FinanceiroLancamentoEdicaoResultado(
        sucesso: false,
        mensagemErro: 'Armazenamento financeiro indisponível.',
      );
    }

    final existente = FinanceiroLancamentoLegacyResolver.buscarNoHive(
          box.values,
          lancamento,
        ) ??
        (lancamento.key != null ? box.get(lancamento.key) : null) ??
        (lancamento.id.trim().isNotEmpty ? box.get(lancamento.id) : null);

    if (existente == null) {
      return const FinanceiroLancamentoEdicaoResultado(
        sucesso: false,
        mensagemErro: 'Lançamento não encontrado para edição.',
      );
    }

    final dadosAnteriores = {
      'descricao': existente.descricao,
      'valor': existente.valor,
      'dataLancamento': existente.dataLancamento.toIso8601String(),
      'dataPagamento': existente.dataPagamento?.toIso8601String(),
      'categoria': existente.categoria,
      'formaPagamento': existente.formaPagamento,
      'observacao': existente.observacao,
    };

    existente.descricao = campos.descricao.trim();
    existente.valor = campos.valor;
    existente.dataLancamento = campos.dataLancamento;
    existente.dataPagamento = campos.dataPagamento;
    existente.categoria = campos.categoria.trim();
    existente.formaPagamento = campos.formaPagamento.trim();
    existente.observacao = campos.observacao.trim();
    existente.competenciaMes = campos.dataLancamento.month;
    existente.competenciaAno = campos.dataLancamento.year;

    final key = existente.key;
    if (key != null) {
      await box.put(key, existente);
    } else if (existente.id.trim().isNotEmpty) {
      await box.put(existente.id, existente);
    }

    final usuario = await _usuarioAtual();
    await FinanceiroFirestoreService.editarLancamentoManual(
      l: existente,
      editadoPor: usuario,
      motivoEdicao: motivoEdicao.trim(),
      dadosAnteriores: dadosAnteriores,
    );

    debugPrint('[FIN-GESTAO][RESULTADO] editar ok id=${existente.id}');
    return const FinanceiroLancamentoEdicaoResultado(sucesso: true);
  }
}
