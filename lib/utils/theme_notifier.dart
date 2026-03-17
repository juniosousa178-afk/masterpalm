// lib/utils/theme_notifier.dart
// Notificador global para modo escuro – garante que a alteração no menu dispare a atualização do tema.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// ValueNotifier global para o modo escuro.
final ValueNotifier<bool> darkModeNotifier = ValueNotifier<bool>(false);

/// Inicializa o valor a partir do Hive (chamar após abrir a box 'config').
void initDarkModeFromHive() {
  try {
    if (Hive.isBoxOpen('config')) {
      final v = Hive.box('config').get('dark_mode');
      darkModeNotifier.value = v == true;
    }
  } catch (_) {}
}

/// Atualiza o modo escuro: salva no Hive e notifica a UI imediatamente.
void setDarkMode(bool value) {
  try {
    if (Hive.isBoxOpen('config')) {
      Hive.box('config').put('dark_mode', value);
    }
    darkModeNotifier.value = value;
  } catch (_) {
    darkModeNotifier.value = value;
  }
}
