// lib/utils/moeda_input_formatter.dart
// Formata dígitos como centavos → "X,XX" (ex: 500 → 5,00 | 5000 → 50,00)

import 'package:flutter/services.dart';

/// Formata entrada de dígitos como valor em reais (centavos → X,XX).
/// Ex: digitar 500 → exibe 5,00 | 5000 → 50,00
class MoedaInputFormatter extends TextInputFormatter {
  MoedaInputFormatter({
    this.maxReais = 999999.99,
    this.allowEmpty = true,
  });

  final double maxReais;
  final bool allowEmpty;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return TextEditingValue(
        text: allowEmpty ? '' : '0,00',
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
    var cents = int.tryParse(digits) ?? 0;
    final maxCents = (maxReais * 100).round();
    if (cents > maxCents) cents = maxCents;

    final intPart = cents ~/ 100;
    final decPart = cents % 100;
    final formatted = '$intPart,${decPart.toString().padLeft(2, '0')}';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Converte texto formatado "5,00" em double 5.0
  static double parse(String text) {
    final digits = text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return 0;
    return (int.tryParse(digits) ?? 0) / 100.0;
  }

  /// Converte double 5.0 em texto formatado "5,00"
  static String format(double value) {
    if (value == 0) return '';
    final cents = (value * 100).round();
    final intPart = cents ~/ 100;
    final decPart = cents % 100;
    return '$intPart,${decPart.toString().padLeft(2, '0')}';
  }
}
