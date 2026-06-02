// Baixa parcial/total de contas a receber com validação e histórico.

import '../models/conta_receber.dart';
import 'conta_receber_recebimento_caixa_service.dart';

class ResultadoBaixaContaReceber {
  final bool sucesso;
  final String? mensagemErro;
  final String? mensagemSucesso;
  final bool quitado;
  final double saldoRestante;

  const ResultadoBaixaContaReceber({
    required this.sucesso,
    this.mensagemErro,
    this.mensagemSucesso,
    this.quitado = false,
    this.saldoRestante = 0,
  });
}

class ContaReceberService {
  ContaReceberService._();

  static void validarValorBaixa({
    required double valorRecebido,
    required double saldoRestante,
  }) {
    if (valorRecebido <= 1e-9) {
      throw ArgumentError('Informe um valor recebido maior que zero.');
    }
    if (valorRecebido > saldoRestante + 0.01) {
      throw ArgumentError('Valor recebido maior que o saldo em aberto.');
    }
  }

  /// Aplica baixa na conta (memória). Não grava Hive nem caixa.
  static void aplicarBaixaNaConta({
    required ContaReceber conta,
    required double valorRecebido,
    required String formaPagamento,
    required DateTime dataRecebimento,
  }) {
    conta.normalizarCamposFinanceiros();
    validarValorBaixa(
      valorRecebido: valorRecebido,
      saldoRestante: conta.saldoRestante,
    );

    conta.valorPago += valorRecebido;
    conta.valor = (conta.saldoRestante - valorRecebido).clamp(0.0, double.infinity);
    if (conta.valor < 0.01) {
      conta.valor = 0;
    }
    conta.adicionarPagamentoHistorico(
      valorRecebido: valorRecebido,
      data: dataRecebimento,
      formaPagamento: formaPagamento,
    );
    conta.recalcularStatus();
  }

  /// Registra recebimento no caixa e persiste a conta.
  static Future<ResultadoBaixaContaReceber> registrarBaixa({
    required ContaReceber conta,
    required double valorRecebido,
    required String formaPagamento,
    required String lojaId,
    required int contaHiveKey,
    int parcelaNumero = 1,
    DateTime? dataRecebimento,
  }) async {
    final saldoAntes = conta.saldoRestante;
    try {
      validarValorBaixa(
        valorRecebido: valorRecebido,
        saldoRestante: saldoAntes,
      );
    } on ArgumentError catch (e) {
      return ResultadoBaixaContaReceber(
        sucesso: false,
        mensagemErro: e.message?.toString() ?? e.toString(),
      );
    }

    final quando = dataRecebimento ?? DateTime.now();
    final docId = await ContaReceberRecebimentoCaixaService.registrarRecebimento(
      lojaId: lojaId,
      valor: valorRecebido,
      formaPagamento: formaPagamento,
      clienteNome: conta.clienteNome,
      observacaoConta: conta.observacao,
      contaHiveKey: contaHiveKey,
      parcelaNumero: parcelaNumero,
      dataRecebimento: quando,
    );
    if (docId == null) {
      return const ResultadoBaixaContaReceber(
        sucesso: false,
        mensagemErro: 'Não foi possível registrar o recebimento no caixa.',
      );
    }

    aplicarBaixaNaConta(
      conta: conta,
      valorRecebido: valorRecebido,
      formaPagamento: formaPagamento,
      dataRecebimento: quando,
    );
    await conta.save();

    final quitado = conta.pago;
    final saldo = conta.saldoRestante;
    final msg = quitado
        ? 'Recebimento registrado. Conta quitada.'
        : 'Pagamento parcial registrado. Saldo restante: R\$ ${saldo.toStringAsFixed(2).replaceAll('.', ',')}.';

    return ResultadoBaixaContaReceber(
      sucesso: true,
      mensagemSucesso: msg,
      quitado: quitado,
      saldoRestante: saldo,
    );
  }
}
