// Compatibilidade segura com lançamentos financeiros antigos (pré mp_cr2 / auditoria).

import 'package:flutter/foundation.dart';

import '../financeiro/financeiro_constants.dart';
import '../models/conta_receber.dart';
import '../models/lancamento_financeiro.dart';
import 'conta_receber_lancamento_vinculo.dart';
import 'conta_pagar_lancamento_vinculo.dart';

enum FinanceiroLancamentoLegadoTipo {
  manual,
  baixaContaReceber,
  outroVinculado,
}

class FinanceiroLancamentoLegadoInfo {
  const FinanceiroLancamentoLegadoInfo({
    required this.tipo,
    this.legado = false,
    this.vinculoCrSeguro = false,
    this.motivoBloqueioEstorno,
  });

  final FinanceiroLancamentoLegadoTipo tipo;
  final bool legado;
  final bool vinculoCrSeguro;
  final String? motivoBloqueioEstorno;

  bool get ehManual => tipo == FinanceiroLancamentoLegadoTipo.manual;
  bool get ehBaixaCr => tipo == FinanceiroLancamentoLegadoTipo.baixaContaReceber;
}

abstract final class FinanceiroLancamentoLegacyResolver {
  FinanceiroLancamentoLegacyResolver._();

  static const msgEstornoLegadoSemVinculo =
      'Não foi possível estornar automaticamente este lançamento antigo porque o vínculo com a parcela não foi encontrado com segurança.';

  static bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _normNome(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool _idCrLegado(String id) {
    final s = id.trim();
    if (s.isEmpty) return false;
    if (s.contains('orfao') || s.contains('invalido')) return false;
    return s.startsWith('mp_cr_') || s.startsWith('mp_cr2_');
  }

  static bool _refCrLegada(String ref) {
    final r = ref.trim();
    if (r.isEmpty) return false;
    if (r.startsWith('cr_receb:orfao')) return false;
    return r.startsWith('cr_receb:') ||
        r.startsWith('cr_receb2:') ||
        r.startsWith('mp_cr2_') ||
        r.startsWith('mp_cr_');
  }

  static String? clienteDeDescricaoRecebimento(String descricao) {
    const prefixo = 'Recebimento — ';
    final d = descricao.trim();
    if (!d.startsWith(prefixo)) return null;
    final nome = d.substring(prefixo.length).trim();
    return nome.isEmpty ? null : nome;
  }

  static bool pareceBaixaContaReceber(LancamentoFinanceiro l) {
    if (lancamentoVinculadoAContaReceber(l)) return true;
    final obs = l.observacao.trim().toLowerCase();
    if (obs.contains('conta a receber')) return true;
    if (l.categoria.trim() == 'recebimentos_fiado' &&
        l.tipo == FinanceiroTipoLancamento.entradaExtra &&
        clienteDeDescricaoRecebimento(l.descricao) != null) {
      return true;
    }
    return false;
  }

  static bool pareceManualLegado(LancamentoFinanceiro l) {
    if (lancamentoVinculadoAContaPagar(l)) return false;
    if (pareceBaixaContaReceber(l)) return false;
    if (l.origem == FinanceiroOrigemLancamento.geradoGastoFixo) return false;
    final ref = l.referenciaExterna.trim().toLowerCase();
    if (ref.startsWith('cp_pag:')) return false;
    if (ref.contains('mercadopago')) return false;
    if (_idCrLegado(l.id) || _refCrLegada(l.referenciaExterna)) return false;
    return true;
  }

  static bool _temRefEstruturada(LancamentoFinanceiro l) {
    final ref = recebimentoRefFromLancamento(l);
    if (ref == null) return false;
    return ref.isFirestoreDocBaixa || ref.isStable || ref.hiveKey != null;
  }

  static ContaReceber? resolverContaPorRef({
    required Iterable<ContaReceber> contas,
    required String lojaId,
    required ContaReceberRecebimentoRefParsed ref,
  }) {
    for (final c in contas) {
      if (c.lojaId.trim() != lojaId.trim()) continue;
      if (ref.isFirestoreDocBaixa) {
        final doc = (c.idFirebase ?? '').trim();
        if (doc == ref.contaReceberDocId) return c;
      } else if (ref.isStable && contaReceberStableId(c) == ref.stableId) {
        return c;
      } else if (ref.hiveKey != null && c.key == ref.hiveKey) {
        return c;
      }
    }
    return null;
  }

  static ContaReceber? resolverContaHeuristica({
    required Iterable<ContaReceber> contas,
    required String lojaId,
    required LancamentoFinanceiro l,
  }) {
    final cliente = clienteDeDescricaoRecebimento(l.descricao);
    if (cliente == null) return null;

    final quando = l.dataPagamento ?? l.dataLancamento;
    final alvo = _normNome(cliente);
    final candidatos = <ContaReceber>[];

    for (final c in contas) {
      if (c.lojaId.trim() != lojaId.trim()) continue;
      if (_normNome(c.clienteNome) != alvo) continue;

      var bate = false;
      for (final h in c.historicoPagamentos()) {
        final v = (h['valor'] as num?)?.toDouble() ?? 0;
        if ((v - l.valor).abs() > 0.02) continue;
        final raw = h['data']?.toString() ?? '';
        final dt = DateTime.tryParse(raw);
        if (dt != null && _mesmoDia(dt, quando)) {
          bate = true;
          break;
        }
      }
      if (bate) candidatos.add(c);
    }

    if (candidatos.length == 1) return candidatos.first;
    return null;
  }

  static FinanceiroLancamentoLegadoInfo classificar(
    LancamentoFinanceiro l, {
    Iterable<ContaReceber> contas = const [],
    String lojaId = '',
  }) {
    debugPrint(
      '[FIN-LEGACY][DETECT] id=${l.id} origem=${l.origem} '
      'ref=${l.referenciaExterna}',
    );

    if (lancamentoVinculadoAContaPagar(l)) {
      return const FinanceiroLancamentoLegadoInfo(
        tipo: FinanceiroLancamentoLegadoTipo.outroVinculado,
      );
    }

    if (!pareceBaixaContaReceber(l)) {
      final legado = pareceManualLegado(l);
      if (legado) debugPrint('[FIN-LEGACY][MANUAL] id=${l.id}');
      return FinanceiroLancamentoLegadoInfo(
        tipo: FinanceiroLancamentoLegadoTipo.manual,
        legado: legado,
      );
    }

    final ref = recebimentoRefFromLancamento(l);
    ContaReceber? conta;
    if (lojaId.isNotEmpty && contas.isNotEmpty) {
      if (ref != null) {
        conta = resolverContaPorRef(contas: contas, lojaId: lojaId, ref: ref);
      }
      conta ??= resolverContaHeuristica(
        contas: contas,
        lojaId: lojaId,
        l: l,
      );
    }

    final refEstruturada = _temRefEstruturada(l);
    final vinculoSeguro =
        conta != null && (refEstruturada || clienteDeDescricaoRecebimento(l.descricao) != null);

    if (vinculoSeguro) {
      debugPrint('[FIN-LEGACY][CR-VINCULO-OK] id=${l.id}');
      return FinanceiroLancamentoLegadoInfo(
        tipo: FinanceiroLancamentoLegadoTipo.baixaContaReceber,
        legado: !refEstruturada || l.referenciaExterna.trim().isEmpty,
        vinculoCrSeguro: true,
      );
    }

    debugPrint('[FIN-LEGACY][CR-VINCULO-FALHOU] id=${l.id}');
    return FinanceiroLancamentoLegadoInfo(
      tipo: FinanceiroLancamentoLegadoTipo.baixaContaReceber,
      legado: true,
      vinculoCrSeguro: false,
      motivoBloqueioEstorno: msgEstornoLegadoSemVinculo,
    );
  }

  static LancamentoFinanceiro? buscarNoHive(
    Iterable<LancamentoFinanceiro> valores,
    LancamentoFinanceiro alvo,
  ) {
    if (alvo.key != null) {
      for (final v in valores) {
        if (v.key == alvo.key) return v;
      }
    }
    final id = alvo.id.trim();
    if (id.isNotEmpty) {
      for (final v in valores) {
        if (v.id.trim() == id) return v;
      }
    }
    return null;
  }
}
