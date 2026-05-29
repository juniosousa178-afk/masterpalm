// Detecção de possível duplicidade ao lançar compra_mercadoria manualmente.

import 'package:hive/hive.dart';

import '../core/conta_pagar_lancamento_vinculo.dart';
import '../financeiro/financeiro_constants.dart';
import '../models/compra_fornecedor.dart';
import '../models/compra_fornecedor_constants.dart';
import '../models/conta_pagar.dart';
import '../models/conta_pagar_constants.dart';
import '../models/lancamento_financeiro.dart';
import 'compra_fornecedor_hive_store.dart';
import 'conta_pagar_hive_store.dart';
import 'financeiro_hive_store.dart';

/// Uma correspondência suspeita (somente para aviso ao usuário).
class DuplicidadeSuspeita {
  const DuplicidadeSuspeita({
    required this.fonte,
    required this.resumo,
    this.detalhe = '',
  });

  /// `conta_pagar` | `lancamento_cp` | `compra_fornecedor` | `lancamento_manual`
  final String fonte;
  final String resumo;
  final String detalhe;
}

abstract final class FinanceiroAntiDuplicidadeService {
  FinanceiroAntiDuplicidadeService._();

  static const int janelaDias = 7;
  static const double toleranciaValor = 0.02;

  static bool valoresParecidos(double a, double b) =>
      (a - b).abs() < toleranciaValor;

  static bool datasNaJanela(DateTime ref, DateTime outra, {int dias = janelaDias}) {
    final diff = ref.difference(outra).inDays.abs();
    return diff <= dias;
  }

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool fornecedoresParecidos(String a, String b) {
    final na = _norm(a);
    final nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return true;
    if (na == nb) return true;
    return na.contains(nb) || nb.contains(na);
  }

  static bool descricoesParecidas(String a, String b) {
    final na = _norm(a);
    final nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    final ta = na.split(' ').where((w) => w.length > 2).toSet();
    final tb = nb.split(' ').where((w) => w.length > 2).toSet();
    if (ta.isEmpty || tb.isEmpty) return false;
    final inter = ta.intersection(tb).length;
    return inter >= 1 && inter >= (ta.length < tb.length ? ta.length : tb.length) / 2;
  }

  static DateTime _dataRefLancamento(LancamentoFinanceiro l) =>
      l.dataEfetivaPagamentoOuLancamento;

  /// Suspeitas ao salvar [candidato] tipo compra_mercadoria (não bloqueia sozinha).
  static Future<List<DuplicidadeSuspeita>> suspeitasCompraMercadoria({
    required String lojaId,
    required LancamentoFinanceiro candidato,
    String? excluirLancamentoId,
    Box<LancamentoFinanceiro>? lancamentosBox,
    Box<ContaPagar>? contasPagarBox,
    Box<CompraFornecedor>? comprasBox,
  }) async {
    if (candidato.tipo != FinanceiroTipoLancamento.compraMercadoria) {
      return const [];
    }

    final lid = lojaId.trim();
    if (lid.isEmpty) return const [];

    final lancBox =
        lancamentosBox ?? await FinanceiroHiveStore.openLancamentosBox(lid);
    final cpBox = contasPagarBox ?? await ContaPagarHiveStore.openBox(lid);
    final compraBox =
        comprasBox ?? await CompraFornecedorHiveStore.openBox(lid);

    final out = <DuplicidadeSuspeita>[];
    final valor = candidato.valor.abs();
    final dataRef = _dataRefLancamento(candidato);
    final forn = candidato.fornecedor;
    final desc = candidato.descricao;

    if (lancBox != null) {
      out.addAll(
        _suspeitasLancamentoManual(
          lancBox: lancBox,
          lojaId: lid,
          candidato: candidato,
          valor: valor,
          dataRef: dataRef,
          excluirId: excluirLancamentoId,
        ),
      );
      out.addAll(
        _suspeitasLancamentoContaPagar(
          lancBox: lancBox,
          lojaId: lid,
          valor: valor,
          dataRef: dataRef,
          forn: forn,
          desc: desc,
          excluirId: excluirLancamentoId,
        ),
      );
    }

    if (cpBox != null) {
      out.addAll(
        _suspeitasContaPagarPaga(
          cpBox: cpBox,
          lojaId: lid,
          valor: valor,
          dataRef: dataRef,
          forn: forn,
        ),
      );
    }

    if (compraBox != null) {
      out.addAll(
        _suspeitasCompraFornecedor(
          compraBox: compraBox,
          lojaId: lid,
          valor: valor,
          dataRef: dataRef,
          forn: forn,
          desc: desc,
        ),
      );
    }

    return out;
  }

  static List<DuplicidadeSuspeita> _suspeitasLancamentoManual({
    required Box<LancamentoFinanceiro> lancBox,
    required String lojaId,
    required LancamentoFinanceiro candidato,
    required double valor,
    required DateTime dataRef,
    String? excluirId,
  }) {
    final alvo = _norm(candidato.descricao);
    if (alvo.isEmpty) return const [];

    final out = <DuplicidadeSuspeita>[];
    for (final x in lancBox.values) {
      if (x.lojaId.trim() != lojaId) continue;
      if (excluirId != null && x.id == excluirId) continue;
      if (lancamentoVinculadoAContaPagar(x)) continue;
      if (x.tipo != FinanceiroTipoLancamento.compraMercadoria) continue;
      if (x.status != FinanceiroStatusLancamento.pago) continue;
      if (!valoresParecidos(x.valor.abs(), valor)) continue;
      if (!datasNaJanela(dataRef, _dataRefLancamento(x))) continue;
      if (_norm(x.descricao) != alvo) continue;
      out.add(
        DuplicidadeSuspeita(
          fonte: 'lancamento_manual',
          resumo:
              'Lançamento manual · ${x.descricao.isEmpty ? '(sem descrição)' : x.descricao}',
          detalhe:
              'R\$ ${x.valor.toStringAsFixed(2)} · ${_fmtData(_dataRefLancamento(x))}',
        ),
      );
      if (out.length >= 3) break;
    }
    return out;
  }

  static List<DuplicidadeSuspeita> _suspeitasLancamentoContaPagar({
    required Box<LancamentoFinanceiro> lancBox,
    required String lojaId,
    required double valor,
    required DateTime dataRef,
    required String forn,
    required String desc,
    String? excluirId,
  }) {
    final out = <DuplicidadeSuspeita>[];
    for (final x in lancBox.values) {
      if (x.lojaId.trim() != lojaId) continue;
      if (excluirId != null && x.id == excluirId) continue;
      if (!lancamentoVinculadoAContaPagar(x)) continue;
      if (x.status != FinanceiroStatusLancamento.pago) continue;
      if (!valoresParecidos(x.valor.abs(), valor)) continue;
      if (!datasNaJanela(dataRef, _dataRefLancamento(x))) continue;
      if (!fornecedoresParecidos(forn, x.fornecedor) &&
          !descricoesParecidas(desc, x.descricao)) {
        continue;
      }
      out.add(
        DuplicidadeSuspeita(
          fonte: 'lancamento_cp',
          resumo: x.descricao.isEmpty
              ? 'Pagamento de Conta a Pagar (automático)'
              : x.descricao,
          detalhe:
              'R\$ ${x.valor.toStringAsFixed(2)} · ${_fmtData(_dataRefLancamento(x))}',
        ),
      );
      if (out.length >= 3) break;
    }
    return out;
  }

  static List<DuplicidadeSuspeita> _suspeitasContaPagarPaga({
    required Box<ContaPagar> cpBox,
    required String lojaId,
    required double valor,
    required DateTime dataRef,
    required String forn,
  }) {
    final out = <DuplicidadeSuspeita>[];
    for (final c in cpBox.values) {
      if (c.lojaId.trim() != lojaId) continue;
      if (c.status != ContaPagarStatus.pago) continue;
      if (!valoresParecidos(c.valorParcela, valor)) continue;
      final d = c.dataPagamento ?? c.atualizadoEm;
      if (!datasNaJanela(dataRef, d)) continue;
      if (!fornecedoresParecidos(forn, c.fornecedorNome)) continue;
      out.add(
        DuplicidadeSuspeita(
          fonte: 'conta_pagar',
          resumo:
              'Conta a Pagar paga · ${c.fornecedorNome} (${c.parcelaNumero}/${c.parcelaTotal})',
          detalhe:
              'R\$ ${c.valorParcela.toStringAsFixed(2)} · pago em ${_fmtData(d)}',
        ),
      );
      if (out.length >= 3) break;
    }
    return out;
  }

  static List<DuplicidadeSuspeita> _suspeitasCompraFornecedor({
    required Box<CompraFornecedor> compraBox,
    required String lojaId,
    required double valor,
    required DateTime dataRef,
    required String forn,
    required String desc,
  }) {
    final out = <DuplicidadeSuspeita>[];
    for (final c in compraBox.values) {
      if (c.lojaId.trim() != lojaId) continue;
      if (c.statusCompra != CompraFornecedorStatusCompra.confirmada) continue;
      final total = c.valorTotalFinanceiro;
      if (!valoresParecidos(total, valor) &&
          !valoresParecidos(c.valorEmAberto, valor) &&
          !valoresParecidos(c.valorPago, valor)) {
        continue;
      }
      if (!datasNaJanela(dataRef, c.dataCompra)) continue;
      if (!fornecedoresParecidos(forn, c.fornecedorNome) &&
          !descricoesParecidas(desc, c.observacao) &&
          !descricoesParecidas(desc, c.referenciaInterna)) {
        continue;
      }
      out.add(
        DuplicidadeSuspeita(
          fonte: 'compra_fornecedor',
          resumo:
              'Compra fornecedor · ${c.fornecedorNome} (${CompraFornecedorTipo.legivel(c.tipoCompra)})',
          detalhe:
              'Total R\$ ${total.toStringAsFixed(2)} · compra ${_fmtData(c.dataCompra)}',
        ),
      );
      if (out.length >= 3) break;
    }
    return out;
  }

  static String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
