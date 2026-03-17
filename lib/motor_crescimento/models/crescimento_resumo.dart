// lib/motor_crescimento/models/crescimento_resumo.dart
// Resumo de crescimento da loja para o painel na home.

/// Resumo agregado para o Painel de Crescimento (home).
class CrescimentoResumo {
  final int produtosParados;
  final int estoqueBaixo;
  final int produtosTopVenda;
  final int carrinhosAbandonados;
  final double ticketMedio;
  final double metaMes;

  const CrescimentoResumo({
    this.produtosParados = 0,
    this.estoqueBaixo = 0,
    this.produtosTopVenda = 0,
    this.carrinhosAbandonados = 0,
    this.ticketMedio = 0.0,
    this.metaMes = 0.0,
  });
}
