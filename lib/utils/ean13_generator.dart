// lib/utils/ean13_generator.dart
// Geração de código EAN-13 válido (sem custo de API). Uso interno/cadastro de produtos.

import 'dart:math';

/// Gera dígito verificador EAN-13 (padrão GS1).
/// [digitos12] deve ter exatamente 12 caracteres numéricos.
int _digitoVerificadorEAN13(String digitos12) {
  if (digitos12.length != 12) return 0;
  int sum = 0;
  for (int i = 0; i < 12; i++) {
    final d = int.tryParse(digitos12[i]) ?? 0;
    sum += (i.isEven ? 1 : 3) * d;
  }
  final r = sum % 10;
  return r == 0 ? 0 : 10 - r;
}

/// Gera um código EAN-13 válido.
/// [prefixo] opcional: ex. "789" (Brasil). Se null, usa "789" + 9 dígitos únicos.
/// [semente] opcional: para reprodutibilidade (ex. key do produto).
String gerarEAN13({String? prefixo, int? semente}) {
  const padrao = '789'; // prefixo comum no Brasil
  final pre = (prefixo ?? padrao).replaceAll(RegExp(r'[^0-9]'), '');
  String base12;
  if (pre.length >= 12) {
    base12 = pre.substring(0, 12);
  } else {
    final rnd = Random(semente ?? DateTime.now().millisecondsSinceEpoch);
    final restante = 12 - pre.length;
    final sb = StringBuffer(pre);
    for (int i = 0; i < restante; i++) {
      sb.write(rnd.nextInt(10));
    }
    base12 = sb.toString();
  }
  final dig = _digitoVerificadorEAN13(base12);
  return '$base12$dig';
}
