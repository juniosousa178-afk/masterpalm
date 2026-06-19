// Regras de ação segura (editar / excluir / estornar) por origem e vínculo.

import 'package:flutter/foundation.dart';

import '../financeiro/financeiro_constants.dart';
import '../models/conta_receber.dart';
import '../models/lancamento_financeiro.dart';
import 'conta_pagar_lancamento_vinculo.dart';
import 'financeiro_lancamento_duplicidade_resolver.dart';
import 'financeiro_lancamento_legacy_resolver.dart';

enum FinanceiroLancamentoAcaoTipo {
  editar,
  excluir,
  estornarBaixa,
  bloqueado,
}

class FinanceiroLancamentoAcaoInfo {
  const FinanceiroLancamentoAcaoInfo({
    required this.podeEditar,
    required this.podeExcluir,
    required this.podeEstornar,
    required this.ehBaixaCr,
    required this.ehManual,
    this.podeExcluirSomenteFinanceiro = false,
    this.podeExcluirDuplicadoBaixaCr = false,
    this.bloqueadoEstorno = false,
    this.bloqueadoGeral = false,
    this.motivoBloqueio,
    this.lancamentoEquivalenteId,
    this.legado = const FinanceiroLancamentoLegadoInfo(
      tipo: FinanceiroLancamentoLegadoTipo.manual,
    ),
  });

  final bool podeEditar;
  final bool podeExcluir;
  final bool podeEstornar;
  final bool podeExcluirSomenteFinanceiro;
  final bool podeExcluirDuplicadoBaixaCr;
  final bool ehBaixaCr;
  final bool ehManual;
  final bool bloqueadoEstorno;
  final bool bloqueadoGeral;
  final String? motivoBloqueio;
  final String? lancamentoEquivalenteId;
  final FinanceiroLancamentoLegadoInfo legado;

  bool get mostrarEstornar =>
      ehBaixaCr && podeEstornar && !podeExcluirDuplicadoBaixaCr;
  bool get mostrarExcluirSomenteFinanceiro =>
      ehBaixaCr && podeExcluirSomenteFinanceiro;
  bool get mostrarExcluirDuplicado =>
      ehBaixaCr && podeExcluirDuplicadoBaixaCr;
  bool get mostrarExcluir => podeExcluir && !ehBaixaCr;
  bool get mostrarEditar => podeEditar;
}

abstract final class FinanceiroLancamentoAcaoResolver {
  FinanceiroLancamentoAcaoResolver._();

  static const msgVinculoProcesso =
      'Este lançamento não pode ser editado ou excluído diretamente porque está '
      'vinculado a outro processo do sistema.\n'
      'Use a ação correta de estorno ou ajuste o lançamento de origem.';

  static bool _vinculoMercadoPago(LancamentoFinanceiro l) {
    final ref = l.referenciaExterna.trim().toLowerCase();
    return ref.contains('mercadopago') || ref.contains('mercado_pago');
  }

  static bool _vinculoProcessoAutomatico(LancamentoFinanceiro l) {
    if (lancamentoVinculadoAContaPagar(l)) return true;
    if (l.origem == FinanceiroOrigemLancamento.geradoGastoFixo) return true;
    if (_vinculoMercadoPago(l)) return true;
    return false;
  }

  static FinanceiroLancamentoAcaoInfo _aplicarDuplicidade(
    FinanceiroLancamentoAcaoInfo base,
    LancamentoFinanceiro l, {
    Iterable<LancamentoFinanceiro> lancamentosLoja = const [],
    Iterable<ContaReceber> contas = const [],
    String lojaId = '',
  }) {
    if (!base.ehBaixaCr || lancamentosLoja.isEmpty) return base;

    final diag = FinanceiroLancamentoDuplicidadeResolver.diagnosticar(
      alvo: l,
      lancamentos: lancamentosLoja,
      contas: contas,
      lojaId: lojaId,
    );
    if (!diag.podeExcluirDuplicado) return base;

    return FinanceiroLancamentoAcaoInfo(
      podeEditar: false,
      podeExcluir: false,
      podeEstornar: false,
      podeExcluirDuplicadoBaixaCr: true,
      ehBaixaCr: true,
      ehManual: false,
      lancamentoEquivalenteId: diag.lancamentoAManter?.id,
      legado: base.legado,
    );
  }

  static FinanceiroLancamentoAcaoInfo resolver(
    LancamentoFinanceiro l, {
    Iterable<ContaReceber> contas = const [],
    String lojaId = '',
    Iterable<LancamentoFinanceiro> lancamentosLoja = const [],
  }) {
    final legado = FinanceiroLancamentoLegacyResolver.classificar(
      l,
      contas: contas,
      lojaId: lojaId,
    );

    if (FinanceiroStatusLancamento.statusEhFinalizadoLegado(l.status)) {
      debugPrint(
        '[FIN-FINALIZADO][DETECT] id=${l.id} key=${l.key} status=${l.status} '
        'desc=${l.descricao}',
      );
    }

    if (!FinanceiroStatusLancamento.statusLiquidado(l.status)) {
      return FinanceiroLancamentoAcaoInfo(
        podeEditar: legado.ehManual && !_vinculoProcessoAutomatico(l),
        podeExcluir: false,
        podeEstornar: false,
        ehBaixaCr: legado.ehBaixaCr,
        ehManual: legado.ehManual,
        bloqueadoGeral: true,
        motivoBloqueio: 'Somente lançamentos quitados podem ser corrigidos aqui.',
        legado: legado,
      );
    }

    if (_vinculoProcessoAutomatico(l)) {
      debugPrint('[FIN-FINALIZADO][BLOQUEADO] processo-automatico id=${l.id}');
      return FinanceiroLancamentoAcaoInfo(
        podeEditar: false,
        podeExcluir: false,
        podeEstornar: false,
        ehBaixaCr: false,
        ehManual: false,
        bloqueadoGeral: true,
        motivoBloqueio: msgVinculoProcesso,
        legado: legado,
      );
    }

    if (legado.ehBaixaCr) {
      if (legado.vinculoCrSeguro) {
        debugPrint('[FIN-FINALIZADO][CR-ESTORNO-PERMITIDO] id=${l.id}');
        return _aplicarDuplicidade(
          FinanceiroLancamentoAcaoInfo(
            podeEditar: false,
            podeExcluir: false,
            podeEstornar: true,
            ehBaixaCr: true,
            ehManual: false,
            legado: legado,
          ),
          l,
          lancamentosLoja: lancamentosLoja,
          contas: contas,
          lojaId: lojaId,
        );
      }
      debugPrint('[FIN-FINALIZADO][BLOQUEADO] cr-sem-vinculo id=${l.id}');
      return _aplicarDuplicidade(
        FinanceiroLancamentoAcaoInfo(
          podeEditar: false,
          podeExcluir: false,
          podeExcluirSomenteFinanceiro: true,
          podeEstornar: false,
          ehBaixaCr: true,
          ehManual: false,
          bloqueadoEstorno: true,
          motivoBloqueio: legado.motivoBloqueioEstorno ??
              FinanceiroLancamentoLegacyResolver.msgEstornoLegadoSemVinculo,
          legado: legado,
        ),
        l,
        lancamentosLoja: lancamentosLoja,
        contas: contas,
        lojaId: lojaId,
      );
    }

    debugPrint('[FIN-FINALIZADO][MANUAL-PERMITIDO] id=${l.id}');
    return FinanceiroLancamentoAcaoInfo(
      podeEditar: true,
      podeExcluir: true,
      podeEstornar: false,
      ehBaixaCr: false,
      ehManual: true,
      legado: legado,
    );
  }
}
