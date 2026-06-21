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

  static String _diaFromDate(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  static int _centavosFromLancamento(LancamentoFinanceiro l) =>
      (l.valor.abs() * 100).round();

  static int _centavosEfetivos(
    ContaReceberRecebimentoRefParsed ref,
    LancamentoFinanceiro l,
  ) =>
      ref.centavos > 0 ? ref.centavos : _centavosFromLancamento(l);

  static String _diaEfetivo(
    ContaReceberRecebimentoRefParsed ref,
    LancamentoFinanceiro l,
  ) => ref.dia.isNotEmpty ? ref.dia : _diaFromDate(_dataBaixa(l));

  static int _parcelaEfetiva(
    ContaReceberRecebimentoRefParsed ref,
    ContaReceber conta,
  ) =>
      ref.parcelaNumero > 0 ? ref.parcelaNumero : conta.parcelaNumero;

  static bool _ativoParaBuscaDuplicidade(LancamentoFinanceiro l) {
    final s = l.status.trim().toLowerCase();
    if (s == 'excluido' || s == 'estornado' || s == 'cancelado') return false;
    return FinanceiroStatusLancamento.statusLiquidado(l.status);
  }

  static Iterable<LancamentoFinanceiro> lancamentosAtivosParaBusca(
    Iterable<LancamentoFinanceiro> lancamentos,
  ) =>
      lancamentos.where(_ativoParaBuscaDuplicidade);

  static bool _stableCompativelComDocId(String stableId, String docId) {
    final stable = stableId.trim();
    final doc = docId.trim();
    if (stable.isEmpty || doc.isEmpty) return false;
    if (stable == doc) return true;
    if (stable.startsWith('${doc}_p')) return true;
    final vendPart = stable.replaceAll(RegExp(r'_p\d+$'), '');
    return vendPart.isNotEmpty && vendPart == doc;
  }

  static bool _refsApontamMesmaContaSemantica(
    ContaReceberRecebimentoRefParsed a,
    ContaReceberRecebimentoRefParsed b,
  ) {
    if (a.isFirestoreDocBaixa && b.isStable) {
      return _stableCompativelComDocId(b.stableId, a.contaReceberDocId);
    }
    if (b.isFirestoreDocBaixa && a.isStable) {
      return _stableCompativelComDocId(a.stableId, b.contaReceberDocId);
    }
    if (a.isStable && b.isStable) return a.stableId == b.stableId;
    if (a.hiveKey != null && b.hiveKey != null) return a.hiveKey == b.hiveKey;
    return false;
  }

  static bool _mesmaBaixaCrossScheme({
    required ContaReceberRecebimentoRefParsed refA,
    required ContaReceberRecebimentoRefParsed refB,
    required LancamentoFinanceiro lancA,
    required LancamentoFinanceiro lancB,
    required Iterable<ContaReceber> contas,
    required String lojaId,
  }) {
    if (_refsMesmaBaixaSemantica(refA, refB)) return true;

    final contaA = _resolverConta(contas: contas, lojaId: lojaId, ref: refA);
    final contaB = _resolverConta(contas: contas, lojaId: lojaId, ref: refB);
    final mesmaConta = _mesmaConta(contaA, contaB) && contaA != null;
    final mesmaContaSemantica = mesmaConta ||
        (contaA == null &&
            contaB == null &&
            _refsApontamMesmaContaSemantica(refA, refB));
    if (!mesmaContaSemantica) return false;

    final conta = contaA ?? contaB;
    final parcelaA = conta != null
        ? _parcelaEfetiva(refA, conta)
        : refA.parcelaNumero;
    final parcelaB = conta != null
        ? _parcelaEfetiva(refB, conta)
        : refB.parcelaNumero;
    if (parcelaA != parcelaB) return false;

    if (_centavosEfetivos(refA, lancA) != _centavosEfetivos(refB, lancB)) {
      return false;
    }

    final diaA = _diaEfetivo(refA, lancA);
    final diaB = _diaEfetivo(refB, lancB);
    if (diaA.isNotEmpty &&
        diaB.isNotEmpty &&
        diaA != diaB &&
        !_mesmoDia(_dataBaixa(lancA), _dataBaixa(lancB))) {
      return false;
    }

    if (!valoresParecidos(lancA.valor, lancB.valor)) return false;
    if (!_mesmoDia(_dataBaixa(lancA), _dataBaixa(lancB))) return false;

    final esquemaDiferente = (refA.isFirestoreDocBaixa != refB.isFirestoreDocBaixa) ||
        (refA.isStable != refB.isStable) ||
        (refA.hiveKey != refB.hiveKey) ||
        (refA.stableId.isNotEmpty &&
            refB.stableId.isNotEmpty &&
            refA.stableId != refB.stableId);
    return esquemaDiferente;
  }

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
    LancamentoFinanceiro lancA,
    LancamentoFinanceiro lancB, {
    required Iterable<ContaReceber> contas,
    required String lojaId,
  }) {
    final refA = recebimentoRefFromLancamento(lancA);
    final refB = recebimentoRefFromLancamento(lancB);

    if (refA != null && refB != null) {
      if (_refsMesmaBaixaSemantica(refA, refB)) {
        return FinanceiroDuplicidadeConfianca.segura;
      }
      if (_mesmaBaixaCrossScheme(
        refA: refA,
        refB: refB,
        lancA: lancA,
        lancB: lancB,
        contas: contas,
        lojaId: lojaId,
      )) {
        return FinanceiroDuplicidadeConfianca.segura;
      }
      final contaA = _resolverConta(contas: contas, lojaId: lojaId, ref: refA);
      final contaB = _resolverConta(contas: contas, lojaId: lojaId, ref: refB);
      if (_mesmaConta(contaA, contaB) &&
          contaA != null &&
          _parcelaEfetiva(refA, contaA) == _parcelaEfetiva(refB, contaB!) &&
          _centavosEfetivos(refA, lancA) == _centavosEfetivos(refB, lancB) &&
          _diaEfetivo(refA, lancA) == _diaEfetivo(refB, lancB)) {
        return FinanceiroDuplicidadeConfianca.segura;
      }
    }

    if (_camposExatamenteIguais(lancA, lancB) &&
        refA != null &&
        refB != null &&
        (refA.isFirestoreDocBaixa ||
            refA.isStable ||
            refB.isFirestoreDocBaixa ||
            refB.isStable)) {
      return FinanceiroDuplicidadeConfianca.exata;
    }

    final clienteA = _clienteNome(lancA);
    final clienteB = _clienteNome(lancB);
    if (clienteA != null &&
        clienteB != null &&
        _norm(clienteA) == _norm(clienteB) &&
        valoresParecidos(lancA.valor, lancB.valor) &&
        _mesmoDia(_dataBaixa(lancA), _dataBaixa(lancB)) &&
        _norm(lancA.formaPagamento) == _norm(lancB.formaPagamento)) {
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
    for (final l in lancamentosAtivosParaBusca(lancamentos)) {
      if (l.id.trim() == alvo.id.trim() && l.key == alvo.key) continue;
      if (alvo.lojaId.trim().isNotEmpty &&
          l.lojaId.trim().isNotEmpty &&
          alvo.lojaId.trim() != l.lojaId.trim()) {
        continue;
      }
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

  static void _logCardResolver({
    required LancamentoFinanceiro alvo,
    required ContaReceberRecebimentoRefParsed? ref,
    required List<LancamentoFinanceiro> candidatos,
    required FinanceiroLancamentoDuplicidadeDiagnostico? resultado,
  }) {
    final motivos = <String>[];
    if (candidatos.isEmpty) {
      motivos.add('sem-candidatos-ativos-na-hive');
    }
    if (resultado?.motivoBloqueio != null) {
      motivos.add(resultado!.motivoBloqueio!);
    }
    debugPrint(
      '[FIN-DUP][CARD-RESOLVER] '
      'lancamentoId=${alvo.id} '
      'hiveKey=${alvo.key} '
      'referenciaExterna=${alvo.referenciaExterna} '
      'origem=${alvo.origem} '
      'contaReceberId=${ref?.contaReceberDocId ?? ref?.stableId ?? ref?.hiveKey ?? ''} '
      'parcela=${ref?.parcelaNumero ?? ''} '
      'valorCentavos=${ref != null && ref.centavos > 0 ? ref.centavos : _centavosFromLancamento(alvo)} '
      'dataBaixa=${_diaEfetivo(ref ?? const ContaReceberRecebimentoRefParsed(), alvo)} '
      'candidatosEncontrados=${candidatos.length} '
      'motivosDeExclusao=${motivos.join('|')} '
      'decisao=${resultado?.podeExcluirDuplicado == true ? 'excluir-duplicado' : (resultado?.motivoBloqueio ?? 'sem-duplicata')}',
    );
  }

  static FinanceiroLancamentoDuplicidadeDiagnostico diagnosticar({
    required LancamentoFinanceiro alvo,
    required Iterable<LancamentoFinanceiro> lancamentos,
    Iterable<ContaReceber> contas = const [],
    String lojaId = '',
  }) {
    final refAlvoDiag = recebimentoRefFromLancamento(alvo);
    debugPrint(
      '[FIN-DUP][DIAGNOSTICO] id=${alvo.id} key=${alvo.key} '
      'valor=${alvo.valor} ref=${alvo.referenciaExterna}',
    );

    final pool = lancamentosAtivosParaBusca(lancamentos);
    final candidatos = encontrarCandidatos(
      alvo: alvo,
      lancamentos: pool,
      contas: contas,
      lojaId: lojaId,
    );

    if (candidatos.isEmpty) {
      debugPrint('[FIN-DUP][DECISAO] sem-duplicata id=${alvo.id}');
      final vazio = FinanceiroLancamentoDuplicidadeDiagnostico(alvo: alvo);
      _logCardResolver(
        alvo: alvo,
        ref: refAlvoDiag,
        candidatos: candidatos,
        resultado: vazio,
      );
      return vazio;
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

    final resultado = FinanceiroLancamentoDuplicidadeDiagnostico(
      alvo: alvo,
      candidatos: candidatos,
      lancamentoAManter: manter,
      confianca: confianca,
      podeExcluirDuplicado: podeExcluir,
      motivoBloqueio: bloqueio,
      mesmaContaReceber: mesmaCr,
      parcelaBaixadaCorretamente: parcelaOk,
    );
    _logCardResolver(
      alvo: alvo,
      ref: refAlvo,
      candidatos: candidatos,
      resultado: resultado,
    );
    return resultado;
  }
}
