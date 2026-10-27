/// Per-product Pix discount rule shared by the product form and bulk actions.
/// The range mirrors the server editorial validator (`validateEditorial`).
class ProdutoDescontoPix {
  ProdutoDescontoPix._();

  static const double minimo = 0;
  static const double maximo = 100;

  static bool valido(num? v) => v != null && v.isFinite && v >= minimo && v <= maximo;

  /// Bulk input: text, NaN, negatives and values above [maximo] are rejected, never guessed.
  static double? parse(String raw) {
    final v = double.tryParse(raw.trim().replaceAll(',', '.'));
    return valido(v) ? v!.toDouble() : null;
  }

  /// Product form input: unreadable text counts as 0 and out-of-range values are clamped.
  static double normalizarFormulario(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null || v.isNaN) return minimo;
    return v.clamp(minimo, maximo).toDouble();
  }
}
