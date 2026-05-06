// Registra recebimento de contas a receber no módulo financeiro (entrada no fluxo de caixa).

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../financeiro/financeiro_constants.dart';
import '../models/lancamento_financeiro.dart';
import 'financeiro_firestore_service.dart';
import 'financeiro_hive_store.dart';

class ContaReceberRecebimentoCaixaService {
  ContaReceberRecebimentoCaixaService._();

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

  /// Grava [entrada_extra] paga na [dataRecebimento] (competência = mês dessa data) e tenta sync Firestore.
  static Future<void> registrarRecebimento({
    required String lojaId,
    required double valor,
    required String formaPagamento,
    required String clienteNome,
    String observacaoConta = '',
    int? contaHiveKey,
    DateTime? dataRecebimento,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty || valor <= 1e-9) return;

    final box = await FinanceiroHiveStore.openLancamentosBox(loja);
    if (box == null) {
      debugPrint('[CR-CAIXA] Box lançamentos indisponível (loja=$loja)');
      return;
    }

    String usuarioNome = '';
    String usuarioId = '';
    try {
      final sessao = await Hive.openBox('sessao');
      usuarioNome = (sessao.get('usuario_logado') ?? '').toString().trim();
      usuarioId = usuarioNome;
    } catch (_) {}

    final now = DateTime.now();
    final quando = dataRecebimento ?? now;
    final id = const Uuid().v4();
    final ref = contaHiveKey != null
        ? 'cr_receb_${contaHiveKey}_${now.millisecondsSinceEpoch}'
        : 'cr_receb_${now.millisecondsSinceEpoch}';

    final obsConta = observacaoConta.trim();
    final l = LancamentoFinanceiro(
      id: id,
      lojaId: loja,
      descricao: 'Recebimento — $clienteNome',
      valor: valor,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      categoria: 'recebimentos_fiado',
      subcategoria: '',
      status: FinanceiroStatusLancamento.pago,
      formaPagamento: formaPagamento.trim(),
      fornecedor: '',
      observacao: obsConta.isEmpty
          ? 'Conta a receber'
          : 'Conta a receber · $obsConta',
      dataLancamento: quando,
      dataPagamento: quando,
      competenciaMes: quando.month,
      competenciaAno: quando.year,
      recorrente: false,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      usuarioId: usuarioId,
      usuarioNome: usuarioNome,
      referenciaExterna: ref,
    );

    await box.put(id, l);
    try {
      await FinanceiroFirestoreService.upsertLancamento(l);
    } catch (e) {
      debugPrint(
        '[CR-CAIXA] Sync Firestore falhou (type=${e.runtimeType})',
      );
    }
  }
}
