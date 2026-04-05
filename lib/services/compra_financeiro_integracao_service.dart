// Política central compra ↔ financeiro: evitar dupla contagem com custos já lançados.
//
// Auditoria (código atual): [LancamentoFinanceiro] só é criado manualmente em
// `FinanceiroLancamentosScreen`. Não há fluxo automático custo de produto/estoque → financeiro.
// Mesmo assim, o total da compra NÃO é lançado automaticamente: muitos fluxos operacionais
// registram despesas por mercadoria/fornecedor à parte; somar o total da compra duplicaria.

import 'package:flutter/foundation.dart';

import '../core/compra_financeiro_vinculo.dart';
import '../models/compra_fornecedor.dart';
import '../models/compra_fornecedor_constants.dart';

/// Ponto único para decisão e efeitos colaterais (hoje: sem lançamento automático).
class CompraFinanceiroIntegracaoService {
  CompraFinanceiroIntegracaoService._();

  /// Quando `false`, nunca criar/atualizar `LancamentoFinanceiro` pelo total da compra.
  /// Alterar só após nova auditoria e regra de negócio explícita.
  static const bool permiteLancamentoAutomaticoPeloTotalDaCompra = false;

  /// Id reservado para um eventual único lançamento vinculado (merge idempotente).
  /// Não implica que o documento exista — apenas o id canônico.
  static String docIdLancamentoCanonica(String compraId) =>
      lancamentoFinanceiroDocIdParaCompra(compraId);

  /// Chamado após compra persistida no Hive (e antes/depois do sync Firestore da compra).
  /// Não cria linha em `lancamentos_financeiros` enquanto [permiteLancamentoAutomaticoPeloTotalDaCompra] for false.
  static void aplicarAposPersistenciaLocal(CompraFornecedor compra) {
    if (!permiteLancamentoAutomaticoPeloTotalDaCompra) {
      _validarInvarianteOpcional(compra);
      return;
    }
    // Futuro: upsert idempotente em doc canônico, apenas se política explícita permitir.
  }

  /// Compra cancelada: não remove lançamentos financeiros (não criados por este módulo).
  /// Se [idLancamentoFinanceiro] estiver preenchido no futuro, o operador/fluxo específico decide estorno.
  static void aplicarEfeitosCancelamento(CompraFornecedor compra) {
    if (compra.statusCompra != CompraFornecedorStatusCompra.cancelada) return;
    _validarInvarianteOpcional(compra);
  }

  static void _validarInvarianteOpcional(CompraFornecedor c) {
    final id = c.idLancamentoFinanceiro.trim();
    if (id.isEmpty) return;
    final canon = docIdLancamentoCanonica(c.id);
    if (id != canon) {
      debugPrint(
        '[COMPRA-FIN] idLancamentoFinanceiro="$id" difere do canônico "$canon" (compra ${c.id}).',
      );
    }
  }
}
