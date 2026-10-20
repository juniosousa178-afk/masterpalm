/// Garante uma única execução em voo por botão de checkout.
///
/// A flag é marcada de forma síncrona, antes de qualquer `await`, para que dois toques no
/// mesmo frame não criem dois pedidos.
class CheckoutSingleFlight {
  bool _busy = false;

  bool get busy => _busy;

  /// Retorna `false` (sem executar) se já houver uma execução em andamento.
  Future<bool> run(Future<void> Function() action) async {
    if (_busy) return false;
    _busy = true;
    try {
      await action();
      return true;
    } finally {
      _busy = false;
    }
  }
}
