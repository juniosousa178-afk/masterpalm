// Detecção segura de lançamentos financeiros duplicados de baixa de Conta a Receber.

import 'package:flutter/foundation.dart';

import '../financeiro/financeiro_constants.dart';
import '../models/conta_receber.dart';
import '../models/lancamento_financeiro.dart';
import 'conta_receber_lancamento_vinculo.dart';
import 'financeiro_lancamento_legacy_resolver.dart';

enum FinanceiroDuplicidadeConfianca {
  segura,
  exata,
  duvida,
  nenhuma,
}

class FinanceiroLancamentoDuplicidadeDiagnostico {
  const FinanceiroLancamentoDuplicidadeDiagnostico({
    required this.alvo,
    this.candidatos = const [],
    this.lancamentoAManter,
    this.confianca = FinanceiroDuplicidadeConfianca.nenhuma,
    this.podeExcluirDuplicado = false,
    this.motivoBloqueio,
    this.mesmaContaReceber = false,
    this.parcelaBaixadaCorretamente = false,
  });

  final LancamentoFinanceiro alvo;
  final List<LancamentoFinanceiro> candidatos;
  final LancamentoFinanceiro? lancamentoAManter;
  final FinanceiroDuplicidadeConfianca confianca;
  final bool podeExcluirDuplicado;
  final String? motivoBloqueio;
  final bool mesmaContaReceber;
  final bool parcelaBaixadaCorretamente;

  bool get alvoEhDuplicado =>
      lancamentoAManter != null &&
      lancamentoAManter!.id.trim() != alvo.id.trim();
}

abstract final class FinanceiroLancamentoDuplicidadeResolver {
  FinanceiroLancamentoDuplicidadeResolver._();

  static bool valoresParecidos(double a, double b) => (a - b).abs() < 0.02;

  static bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _dataBaixa(LancamentoFinanceiro l) =>
      l.dataPagamento ?? l.dataLancamento;

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String? _clienteNome(LancamentoFinanceiro l) =>
      FinanceiroLancamentoLegacyResolver.clienteDeDescricaoRecebimento(l.descricao);

  static bool _ehBaixaCrLiquidada(LancamentoFinanceiro l) =>
      FinanceiroLancamentoLegacyResolver.pareceBaixaContaReceber(l) &&
      FinanceiroStatusLancamento.statusLiquidado(l.status) &&
      l.lojaId.trim().isNotEmpty;

  static bool _refsMesmaBaixaSemantica(
    ContaReceberRecebimentoRefParsed a,
    ContaReceberRecebimentoRefParsed b,
  ) {
    if (a.isFirestoreDocBaixa && b.isFirestoreDocBaixa) {
      return a.contaReceberDocId == b.contaReceberDocId &&
          a.baixaId == b.baixaId;
    }
    if (a.isStable && b.isStable) {
      return a.stableId == b.stableId &&
          a.parcelaNumero == b.parcelaNumero &&
          a.centavos == b.centavos &&
          a.dia == b.dia;
    }
    if (a.hiveKey != null && b.hiveKey != null) {
      return a.hiveKey == b.hiveKey &&
          a.parcelaNumero == b.parcelaNumero &&
          a.centavos == b.centavos &&
          a.dia == b.dia;
    }
    return a.parcelaNumero == b.parcelaNumero &&
        a.centavos == b.centavos &&
        a.dia == b.dia &&
        a.dia.isNotEmpty;
  }

  static ContaReceber? _resolverConta({
    required Iterable<ContaReceber> contas,
    required String lojaId,
    required ContaReceberRecebimentoRefParsed ref,
  }) =>
      FinanceiroLancamentoLegacyResolver.resolverContaPorRef(
        contas: contas,
        lojaId: lojaId,
        ref: ref,
      );

  static bool _mesmaConta(ContaReceber? a, ContaReceber? b) {
    if (a == null || b == null) return false;
    if (identical(a, b)) return true;
    final docA = (a.idFirebase ?? '').trim();
    final docB = (b.idFirebase ?? '').trim();
    if (docA.isNotEmpty && docB.isNotEmpty && docA == docB) return true;
    final stableA = contaReceberStableId(a);
    final stableB = contaReceberStableId(b);
    if (stableA.isNotEmpty && stableB.isNotEmpty && stableA == stableB) {
      return true;
    }
    return a.key != null && b.key != null && a.key == b.key;
  }

  static FinanceiroDuplicidadeConfianca _confiancaEntre(
    LancamentoFinanceiro a,
    LancamentoFinanceiro b, {
    required Iterable<ContaReceber> contas,
    required String lojaId,
  }) {
    final refA = recebimentoRefFromLancamento(a);
    final refB = recebimentoRefFromLancamento(b);

    if (refA != null && refB != null) {
      if (_refsMesmaBaixaSemantica(refA, refB)) {
        return FinanceiroDuplicidadeConfianca.segura;
      }
      final contaA = _resolverConta(contas: contas, lojaId: lojaId, ref: refA);
      final contaB = _resolverConta(contas: contas, lojaId: lojaId, ref: refB);
      if (_mesmaConta(contaA, contaB) &&
          refA.parcelaNumero == refB.parcelaNumero &&
          refA.centavos == refB.centavos &&
          refA.dia == refB.dia &&
          refA.dia.isNotEmpty) {
        return FinanceiroDuplicidadeConfianca.segura;
      }
    }

    if (_camposExatamenteIguais(a, b)) {
      return FinanceiroDuplicidadeConfianca.exata;
    }

    final clienteA = _clienteNome(a);
    final clienteB = _clienteNome(b);
    if (clienteA != null &&
        clienteB != null &&
        _norm(clienteA) == _norm(clienteB) &&
        valoresParecidos(a.valor, b.valor) &&
        _mesmoDia(_dataBaixa(a), _dataBaixa(b)) &&
        _norm(a.formaPagamento) == _norm(b.formaPagamento)) {
      return FinanceiroDuplicidadeConfianca.duvida;
    }

    return FinanceiroDuplicidadeConfianca.nenhuma;
  }

  static bool _camposExatamenteIguais(
    LancamentoFinanceiro a,
    LancamentoFinanceiro b,
  ) =>
      _norm(a.descricao) == _norm(b.descricao) &&
      valoresParecidos(a.valor, b.valor) &&
      _norm(a.formaPagamento) == _norm(b.formaPagamento) &&
      _norm(a.observacao) == _norm(b.observacao) &&
      _mesmoDia(_dataBaixa(a), _dataBaixa(b)) &&
      _norm(a.origem) == _norm(b.origem);

  static bool saoMesmaBaixaContaReceber(
    LancamentoFinanceiro a,
    LancamentoFinanceiro b, {
    Iterable<ContaReceber> contas = const [],
    String lojaId = '',
  }) {
    if (!_ehBaixaCrLiquidada(a) || !_ehBaixaCrLiquidada(b)) return false;
    if (a.lojaId.trim() != b.lojaId.trim()) return false;
    if (!valoresParecidos(a.valor, b.valor)) return false;
    if (!_mesmoDia(_dataBaixa(a), _dataBaixa(b))) return false;

    final conf = _confiancaEntre(a, b, contas: contas, lojaId: lojaId);
    return conf == FinanceiroDuplicidadeConfianca.segura ||
        conf == FinanceiroDuplicidadeConfianca.exata;
  }

  static int _prioridadeManter(LancamentoFinanceiro l) {
    final ref = l.referenciaExterna.trim();
    var score = 0;
    if (ref.startsWith('cr_receb2:') || ref.startsWith('cr_receb:')) {
      score += 200;
    }
    final parsed = recebimentoRefFromLancamento(l);
    if (parsed?.isFirestoreDocBaixa == true) score += 100;
    if (parsed?.isStable == true) score += 80;
    if (parsed?.hiveKey != null) score += 40;
    return score;
  }

  static LancamentoFinanceiro escolherLancamentoAManter(
    Iterable<LancamentoFinanceiro> grupo,
  ) {
    final list = grupo.toList()
      ..sort((a, b) {
        final cmpData = a.dataLancamento.compareTo(b.dataLancamento);
        if (cmpData != 0) return cmpData;
        final pa = _prioridadeManter(a);
        final pb = _prioridadeManter(b);
        if (pa != pb) return pb.compareTo(pa);
        return a.id.compareTo(b.id);
      });
    return list.first;
  }

  static List<LancamentoFinanceiro> encontrarCandidatos({
    required LancamentoFinanceiro alvo,
    required Iterable<LancamentoFinanceiro> lancamentos,
    Iterable<ContaReceber> contas = const [],
    String lojaId = '',
  }) {
    if (!_ehBaixaCrLiquidada(alvo)) return const [];
    final out = <LancamentoFinanceiro>[];
    for (final l in lancamentos) {
      if (l.id.trim() == alvo.id.trim() && l.key == alvo.key) continue;
      if (!_ehBaixaCrLiquidada(l)) continue;
      if (saoMesmaBaixaContaReceber(
        alvo,
        l,
        contas: contas,
        lojaId: lojaId,
      )) {
        out.add(l);
      }
    }
    return out;
  }

  static LancamentoFinanceiro? encontrarDuplicataExistente({
    required LancamentoFinanceiro candidato,
    required Iterable<LancamentoFinanceiro> lancamentos,
    Iterable<ContaReceber> contas = const [],
    String lojaId = '',
  }) {
    final dupes = encontrarCandidatos(
      alvo: candidato,
      lancamentos: lancamentos,
      contas: contas,
      lojaId: lojaId,
    );
    if (dupes.isEmpty) return null;
    return escolherLancamentoAManter([candidato, ...dupes]);
  }

  static bool _parcelaBaixadaCorretamente({
    required LancamentoFinanceiro alvo,
    required Iterable<ContaReceber> contas,
    required String lojaId,
  }) {
    final ref = recebimentoRefFromLancamento(alvo);
    if (ref == null) return false;
    final conta = _resolverConta(contas: contas, lojaId: lojaId, ref: ref);
    if (conta == null) return false;
    if (conta.pago || conta.saldoRestante <= 0.02) return true;
    return conta.valorPago >= alvo.valor - 0.02;
  }

  static FinanceiroLancamentoDuplicidadeDiagnostico diagnosticar({
    required LancamentoFinanceiro alvo,
    required Iterable<LancamentoFinanceiro> lancamentos,
    Iterable<ContaReceber> contas = const [],
    String lojaId = '',
  }) {
    debugPrint(
      '[FIN-DUP][DIAGNOSTICO] id=${alvo.id} key=${alvo.key} '
      'valor=${alvo.valor} ref=${alvo.referenciaExterna}',
    );

    final candidatos = encontrarCandidatos(
      alvo: alvo,
      lancamentos: lancamentos,
      contas: contas,
      lojaId: lojaId,
    );

    if (candidatos.isEmpty) {
      debugPrint('[FIN-DUP][DECISAO] sem-duplicata id=${alvo.id}');
      return FinanceiroLancamentoDuplicidadeDiagnostico(alvo: alvo);
    }

    debugPrint(
      '[FIN-DUP][CANDIDATOS] alvo=${alvo.id} qtd=${candidatos.length} '
      'ids=${candidatos.map((c) => c.id).join(",")}',
    );

    final grupo = [alvo, ...candidatos];
    final manter = escolherLancamentoAManter(grupo);
    final confs = candidatos
        .map(
          (c) => _confiancaEntre(alvo, c, contas: contas, lojaId: lojaId),
        )
        .toList();
    FinanceiroDuplicidadeConfianca confianca;
    if (confs.any((c) => c == FinanceiroDuplicidadeConfianca.segura)) {
      confianca = FinanceiroDuplicidadeConfianca.segura;
    } else if (confs.any((c) => c == FinanceiroDuplicidadeConfianca.exata)) {
      confianca = FinanceiroDuplicidadeConfianca.exata;
    } else {
      confianca = FinanceiroDuplicidadeConfianca.duvida;
    }

    final refAlvo = recebimentoRefFromLancamento(alvo);
    final refManter = recebimentoRefFromLancamento(manter);
    final contaAlvo = refAlvo == null
        ? null
        : _resolverConta(contas: contas, lojaId: lojaId, ref: refAlvo);
    final contaManter = refManter == null
        ? null
        : _resolverConta(contas: contas, lojaId: lojaId, ref: refManter);
    final mesmaCr = _mesmaConta(contaAlvo, contaManter) ||
        (contaAlvo != null && contaManter != null && identical(contaAlvo, contaManter));

    debugPrint(
      '[FIN-DUP][MESMA-BAIXA] alvo=${alvo.id} manter=${manter.id} '
      'conf=$confianca mesmaCr=$mesmaCr '
      'refAlvo=${alvo.referenciaExterna} refManter=${manter.referenciaExterna}',
    );

    final parcelaOk = _parcelaBaixadaCorretamente(
      alvo: manter,
      contas: contas,
      lojaId: lojaId,
    );

    final alvoEhDuplicado = manter.id.trim() != alvo.id.trim() ||
        (alvo.key != null &&
            manter.key != null &&
            alvo.key != manter.key &&
            manter.id.trim() == alvo.id.trim());

    String? bloqueio;
    var podeExcluir = false;
    if (confianca == FinanceiroDuplicidadeConfianca.duvida) {
      bloqueio =
          'Duplicidade não confirmada com segurança. Solicite análise manual antes de excluir.';
    } else if (!alvoEhDuplicado) {
      bloqueio =
          'Este é o lançamento correto a manter. Exclua o outro lançamento duplicado.';
    } else {
      podeExcluir = true;
    }

    debugPrint(
      '[FIN-DUP][DECISAO] id=${alvo.id} podeExcluir=$podeExcluir '
      'manter=${manter.id} conf=$confianca parcelaOk=$parcelaOk',
    );

    return FinanceiroLancamentoDuplicidadeDiagnostico(
      alvo: alvo,
      candidatos: candidatos,
      lancamentoAManter: manter,
      confianca: confianca,
      podeExcluirDuplicado: podeExcluir,
      motivoBloqueio: bloqueio,
      mesmaContaReceber: mesmaCr,
      parcelaBaixadaCorretamente: parcelaOk,
    );
  }
}
