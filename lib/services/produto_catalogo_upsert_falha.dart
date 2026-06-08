// Registro de falhas parciais ao sincronizar draft/live após save em estoque_produtos.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'produto_sync_erro_util.dart';

/// Resultado da reidratação Hive após save confirmado em estoque_produtos.
class ProdutoRehydratePosSaveResult {
  const ProdutoRehydratePosSaveResult({
    required this.sucesso,
    this.aviso,
  });

  final bool sucesso;
  final String? aviso;
}

/// Falha ao atualizar draft ou live sem bloquear o save em estoque_produtos.
class ProdutoCatalogoUpsertFalha {
  const ProdutoCatalogoUpsertFalha({
    required this.lojaId,
    required this.produtoId,
    required this.path,
    required this.operacao,
    required this.erro,
  });

  final String lojaId;
  final String produtoId;
  final String path;
  final String operacao;
  final String erro;

  static String erroDe(Object error) {
    if (error is FirebaseException) {
      return ProdutoSyncErroUtil.sanitizar(error) ?? error.code;
    }
    if (error is FirebaseAuthException) {
      return ProdutoSyncErroUtil.sanitizar(error) ?? error.code;
    }
    return ProdutoSyncErroUtil.sanitizar(error) ?? error.toString();
  }
}
