// lib/screens/cadastro_produto_screen.dart
//
// COMPATIBILIDADE: o cadastro de produto foi unificado em [ProdutoFormScreen]
// (Hive + estoque_produtos + sincronização). A tela antiga gravava apenas em
// `draft_produtos`; manter este arquivo evita que imports antigos quebrem.
//
import 'package:flutter/material.dart';

import 'produto_form_screen.dart';

/// Redirecionamento para o cadastro unificado.
///
/// O parâmetro [idLoja] é **ignorado**: a loja ativa vem de [LojaIdService] /
/// sessão, igual ao restante do app.
@Deprecated(
  'Use ProdutoFormScreen diretamente. '
  'CadastroProdutoScreen só mantém compatibilidade de API.',
)
class CadastroProdutoScreen extends StatelessWidget {
  const CadastroProdutoScreen({super.key, required this.idLoja});

  /// Mantido por compatibilidade; não é usado na tela unificada.
  final String idLoja;

  @override
  Widget build(BuildContext context) {
    return const ProdutoFormScreen();
  }
}
