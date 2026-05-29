// Sincroniza exclusão/cancelamento entre Contas a Pagar e Financeiro.

import 'package:flutter/foundation.dart';

import '../core/conta_pagar_lancamento_vinculo.dart';
import '../models/conta_pagar.dart';
import '../models/conta_pagar_constants.dart';
import 'conta_pagar_hive_store.dart';
import 'conta_pagar_service.dart';
import 'financeiro_firestore_service.dart';
import 'financeiro_hive_store.dart';

class CancelarContaPagarResultado {
  const CancelarContaPagarResultado({
    required this.contaCancelada,
    this.lancamentoExcluido = false,
    this.lancamentoNaoEncontrado = false,
    this.jaEstavaCancelada = false,
    this.lancamentoFinanceiroId,
  });

  final bool contaCancelada;
  final bool lancamentoExcluido;
  final bool lancamentoNaoEncontrado;
  final bool jaEstavaCancelada;
  final String? lancamentoFinanceiroId;
}

abstract final class ContaPagarFinanceiroExclusaoService {
  ContaPagarFinanceiroExclusaoService._();

  /// Remove lançamento do Hive e Firestore (sem janela de desfazer).
  static Future<bool> excluirLancamentoImediato({
    required String lojaId,
    required String lancamentoId,
  }) async {
    final lid = lojaId.trim();
    final lancId = lancamentoId.trim();
    if (lid.isEmpty || lancId.isEmpty) return false;

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lid);
    if (finBox == null) return false;

    final existente = finBox.get(lancId);
    if (existente == null) return false;

    try {
      await FinanceiroFirestoreService.deleteLancamento(
        lojaId: lid,
        id: lancId,
      );
    } catch (e) {
      debugPrint('[CP-EXCL] Firestore delete LF falhou: $e');
    }
    await finBox.delete(lancId);
    return true;
  }

  static String? _resolverLancamentoId(ContaPagar conta) {
    final gravado = conta.lancamentoFinanceiroId.trim();
    if (gravado.isNotEmpty) return gravado;
    if (conta.status == ContaPagarStatus.pago) {
      return lancamentoFinanceiroDocIdParaContaPagar(conta.id);
    }
    return null;
  }

  /// Cancela parcela; se paga, remove também o lançamento financeiro vinculado.
  static Future<CancelarContaPagarResultado> cancelarContaPagar({
    required String lojaId,
    required ContaPagar conta,
    bool excluirLancamentoVinculado = true,
  }) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) {
      return const CancelarContaPagarResultado(contaCancelada: false);
    }

    if (conta.status == ContaPagarStatus.cancelado) {
      return CancelarContaPagarResultado(
        contaCancelada: true,
        jaEstavaCancelada: true,
        lancamentoFinanceiroId: conta.lancamentoFinanceiroId,
      );
    }

    final cpBox = await ContaPagarHiveStore.openBox(lid);
    if (cpBox == null) {
      return const CancelarContaPagarResultado(contaCancelada: false);
    }

    var lancExcluido = false;
    var lancNaoEncontrado = false;
    String? lancId = _resolverLancamentoId(conta);

    final eraPaga = conta.status == ContaPagarStatus.pago;
    if (excluirLancamentoVinculado && eraPaga && lancId != null) {
      lancExcluido = await excluirLancamentoImediato(
        lojaId: lid,
        lancamentoId: lancId,
      );
      if (!lancExcluido) {
        final finBox = await FinanceiroHiveStore.openLancamentosBox(lid);
        if (finBox?.get(lancId) == null) {
          lancNaoEncontrado = true;
          debugPrint(
            '[CP-EXCL] LF vinculado não encontrado id=$lancId conta=${conta.id}',
          );
        }
      }
    }

    await cpBox.put(
      conta.id,
      conta.copyWith(
        status: ContaPagarStatus.cancelado,
        lancamentoFinanceiroId: '',
        atualizadoEm: DateTime.now(),
      ),
    );

    await ContaPagarService.sincronizarCompraPagamento(lid, conta.compraId);

    return CancelarContaPagarResultado(
      contaCancelada: true,
      lancamentoExcluido: lancExcluido,
      lancamentoNaoEncontrado: lancNaoEncontrado && eraPaga,
      lancamentoFinanceiroId: lancId,
    );
  }

  static Future<CancelarContaPagarResultado> cancelarContaPagarPorId({
    required String lojaId,
    required String contaPagarId,
    bool excluirLancamentoVinculado = true,
  }) async {
    final cpBox = await ContaPagarHiveStore.openBox(lojaId);
    if (cpBox == null) {
      return const CancelarContaPagarResultado(contaCancelada: false);
    }
    final conta = cpBox.get(contaPagarId.trim());
    if (conta == null) {
      return const CancelarContaPagarResultado(contaCancelada: false);
    }
    return cancelarContaPagar(
      lojaId: lojaId,
      conta: conta,
      excluirLancamentoVinculado: excluirLancamentoVinculado,
    );
  }
}
