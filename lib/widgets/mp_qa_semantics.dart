// Semântica mínima para automação Web E2E isolada (R8.4.38).
// Ativo somente com MP_ENVIRONMENT=qa — sem impacto em produção.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../config/mp_environment_config.dart';

/// Envolve [child] com [Semantics] estável quando ambiente QA.
Widget mpQaSemantics(
  String label,
  Widget child, {
  bool button = false,
  bool textField = false,
  bool header = false,
  String? value,
}) {
  if (!MpEnvironmentConfig.isQa) return child;
  return Semantics(
    label: label,
    button: button,
    textField: textField,
    header: header,
    value: value,
    container: true,
    child: child,
  );
}

/// Garante árvore de semântica acessível ao Playwright no Web QA.
void mpQaEnsureSemanticsTree() {
  if (!MpEnvironmentConfig.isQa) return;
  try {
    SemanticsBinding.instance.ensureSemantics();
  } catch (_) {
    // Já inicializado — ignorar.
  }
}
