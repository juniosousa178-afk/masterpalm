// Pagamento de conta a pagar → lançamento financeiro idempotente (caixa).

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/conta_pagar_lancamento_vinculo.dart';
import '../financeiro/financeiro_constants.dart';
import '../models/conta_pagar.dart';
import '../models/lancamento_financeiro.dart';
import 'financeiro_firestore_service.dart';
import 'financeiro_hive_store.dart';

class ContaPagarPagamentoCaixaService {
  ContaPagarPagamentoCaixaService._();

  static List<double> parcelarValores(double total, int parcelas) {
    final qtd = parcelas.clamp(1, 48);
    final totalCentavos = (total * 100).round();
    final base = totalCentavos ~/ qtd;
    final resto = totalCentavos % qtd;
    return List<double>.generate(
      qtd,
      (i) => (base + (i < resto ? 1 : 0)) / 100.0,
    );
  }

  /// Upsert idempotente. Retorna id do lançamento ou null se falhou.
  static Future<String?> registrarPagamento({
    required String lojaId,
    required ContaPagar conta,
    required String formaPagamento,
    required DateTime dataPagamento,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty || conta.valorParcela <= 1e-9) return null;

    final box = await FinanceiroHiveStore.openLancamentosBox(loja);
    if (box == null) {
      debugPrint('[CP-CAIXA] Box lançamentos indisponível (loja=$loja)');
      return null;
    }

    final docId = lancamentoFinanceiroDocIdParaContaPagar(conta.id);
    final ref = referenciaExternaContaPagar(
      contaPagarId: conta.id,
      compraId: conta.compraId,
    );

    final existente = box.get(docId);
    if (existente != null &&
        existente.status == FinanceiroStatusLancamento.pago &&
        (existente.valor - conta.valorParcela).abs() < 0.02) {
      debugPrint('[CP-CAIXA] Lançamento já existe docId=$docId — idempotente.');
      return docId;
    }

    for (final l in box.values) {
      if (l.lojaId != loja) continue;
      if (l.referenciaExterna.trim() == ref &&
          l.status == FinanceiroStatusLancamento.pago) {
        debugPrint('[CP-CAIXA] Ref $ref já paga — idempotente.');
        return l.id;
      }
    }

    String usuarioNome = '';
    String usuarioId = '';
    try {
      final sessao = await Hive.openBox('sessao');
      usuarioNome = (sessao.get('usuario_logado') ?? '').toString().trim();
      usuarioId = usuarioNome;
    } catch (_) {}

    final parcelaTxt = conta.parcelaTotal > 1
        ? ' (${conta.parcelaNumero}/${conta.parcelaTotal})'
        : '';

    final l = LancamentoFinanceiro(
      id: docId,
      lojaId: loja,
      descricao: 'Pagamento compra — ${conta.fornecedorNome}$parcelaTxt',
      valor: conta.valorParcela,
      tipo: FinanceiroTipoLancamento.compraMercadoria,
      categoria: 'compra_produtos',
      subcategoria: '',
      status: FinanceiroStatusLancamento.pago,
      formaPagamento: formaPagamento.trim(),
      fornecedor: conta.fornecedorNome,
      observacao: conta.descricao.trim().isNotEmpty
          ? conta.descricao.trim()
          : 'Conta a pagar · compra ${conta.compraId}',
      dataLancamento: conta.dataCompra,
      dataPagamento: dataPagamento,
      competenciaMes: conta.dataCompra.month,
      competenciaAno: conta.dataCompra.year,
      recorrente: false,
      origem: FinanceiroOrigemLancamento.contaPagarCompra,
      usuarioId: usuarioId,
      usuarioNome: usuarioNome,
      referenciaExterna: ref,
    );

    await box.put(docId, l);
    try {
      await FinanceiroFirestoreService.upsertLancamento(l);
    } catch (e) {
      debugPrint('[CP-CAIXA] Sync Firestore falhou (type=${e.runtimeType})');
    }
    return docId;
  }
}
