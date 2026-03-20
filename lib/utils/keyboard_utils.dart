// lib/utils/keyboard_utils.dart
// Teclado para valores decimais (preço, etc).
// Web/Safari iOS: Flutter não mapeia inputmode="decimal" corretamente, então usamos
// TextInputType.text para exibir teclado completo (tecla "123" mostra números + ponto).
// Mobile nativo: numberWithOptions(decimal: true) funciona.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Teclado para valores decimais (preço, frete, valor).
/// Web (Safari iPhone): usa teclado texto → toque em "123" para números + ponto.
/// Mobile nativo: teclado decimal com ponto/vírgula.
TextInputType get kKeyboardDecimal =>
    kIsWeb ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true);
