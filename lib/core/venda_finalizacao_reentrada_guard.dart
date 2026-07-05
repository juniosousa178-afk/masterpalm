/// Trava síncrona contra dupla submissão na finalização de venda.
class VendaFinalizacaoReentradaGuard {
  bool _emAndamento = false;

  bool get emAndamento => _emAndamento;

  /// Retorna true se esta chamada adquiriu a trava; false se já havia operação em curso.
  bool tentarIniciar() {
    if (_emAndamento) return false;
    _emAndamento = true;
    return true;
  }

  void liberar() {
    _emAndamento = false;
  }
}
