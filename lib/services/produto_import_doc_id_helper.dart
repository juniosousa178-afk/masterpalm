// DocId local (offline) e utilitários de importação — sem Firestore no caminho offline.

import 'package:uuid/uuid.dart';

import '../core/produto_firestore_doc_id_validator.dart';
import '../models/produto.dart';
import 'package:hive/hive.dart';

import '../models/venda.dart';

class ProdutoImportDocIdHelper {
  ProdutoImportDocIdHelper._();

  static const String importLocalIdPrefix = 'import-';

  static bool isDocIdLocalImportacao(String? raw) {
    final id = raw?.trim() ?? '';
    return id.startsWith(importLocalIdPrefix);
  }

  /// ID local seguro para importação offline — zero Firestore.
  static String gerarDocIdLocalSeguro() {
    final id = '$importLocalIdPrefix${const Uuid().v4()}';
    if (!ProdutoFirestoreDocIdValidator.isProdutoIdSeguro(id)) {
      return gerarDocIdLocalSeguro();
    }
    return id;
  }

  static void aplicarDocIdLocalOfflineNoProduto({
    required Produto produto,
    required String lojaId,
  }) {
    produto.slug = gerarDocIdLocalSeguro();
    produto.idFirebase = '';
    produto.lojaId = lojaId;
  }

  static bool produtoTemVendaOuReferencia({
    required Produto produto,
    required Box<Venda> vendasBox,
    required String lojaId,
  }) {
    final ids = <String>{
      produto.idFirebase.trim(),
      produto.slug.trim(),
      if (produto.key != null) produto.key.toString(),
    }..removeWhere((e) => e.isEmpty);

    for (final venda in vendasBox.values) {
      if (venda.lojaId != null &&
          venda.lojaId!.isNotEmpty &&
          venda.lojaId != lojaId) {
        continue;
      }
      for (final item in venda.itensOuVazio) {
        final pid = (item.productId ?? '').trim();
        if (pid.isNotEmpty && ids.contains(pid)) return true;
      }
      final desc = venda.produtosDescricao.trim().toLowerCase();
      if (desc.isNotEmpty &&
          desc == produto.nome.trim().toLowerCase() &&
          venda.quantidade > 0) {
        return true;
      }
    }
    return false;
  }
}
