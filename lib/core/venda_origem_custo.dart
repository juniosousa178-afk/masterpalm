// Valores persistidos em Hive/Firestore — não renomear sem migração.

abstract class VendaOrigemCusto {
  static const produto = 'produto';
  static const item = 'item';
  static const fallback = 'fallback';
  static const zeroIntencional = 'zero_intencional';
  static const desconhecido = 'desconhecido';

  static const Set<String> todos = {
    produto,
    item,
    fallback,
    zeroIntencional,
    desconhecido,
  };

  static String? normalizarOuNull(String? s) {
    if (s == null || s.isEmpty) return null;
    return todos.contains(s) ? s : desconhecido;
  }
}
