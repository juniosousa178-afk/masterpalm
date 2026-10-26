import '../models/produto.dart';

/// Single promotion contract: deactivating has the same effect as switching
/// "Promoção" off in the product form (discount % and R$ cleared, period kept).
/// Normal price, stock and variations are never part of it.
class ProdutoPromocao {
  ProdutoPromocao._();

  static bool temPromocao(Produto p) => p.emPromocao;

  /// Exact editorial patch persisted when a promotion is deactivated.
  static const Map<String, dynamic> camposDesativacao = {
    'emPromocao': false,
    'percentualPromo': null,
    'valorPromo': null,
  };

  /// Returns `false` (and changes nothing) when the product had no promotion.
  static bool desativar(Produto p) {
    if (!p.emPromocao) return false;
    p.emPromocao = false;
    p.percentualPromo = null;
    p.valorPromo = null;
    return true;
  }

  /// Discount persisted by the form: only the chosen type, and nothing when off.
  static ({double? percentual, double? valor}) descontoParaSalvar({
    required bool emPromocao,
    required String tipoDesconto,
    required double Function() lerPercentual,
    required double Function() lerValor,
  }) {
    if (!emPromocao) return (percentual: null, valor: null);
    return tipoDesconto == 'percentual'
        ? (percentual: lerPercentual(), valor: null)
        : (percentual: null, valor: lerValor());
  }
}
