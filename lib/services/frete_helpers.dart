/// Helpers puros de normalização/validação usados por `FreteService`.
/// Não fazem I/O nem acessam Firestore/HTTP.
library;

/// Valida CEP (apenas números, 8 dígitos).
bool freteValidarCep(String cep) {
  final limpo = cep.replaceAll(RegExp(r'[^0-9]'), '');
  return limpo.length == 8;
}

/// Formata CEP (12345678 -> 12345-678).
String freteFormatarCep(String cep) {
  final limpo = cep.replaceAll(RegExp(r'[^0-9]'), '');
  if (limpo.length != 8) return cep;
  return '${limpo.substring(0, 5)}-${limpo.substring(5)}';
}

