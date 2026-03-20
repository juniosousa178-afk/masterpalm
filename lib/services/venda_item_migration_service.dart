// lib/services/venda_item_migration_service.dart
//
// Migração SEGURA e INCREMENTAL para preencher productId em itens de vendas antigas.
// Só preenche quando houver match inequívoco (exatamente 1 produto compatível).
// Não altera dados financeiros, não reprocessa estoque, não usa heurísticas.
//
// Uso: sob demanda (ex.: tela admin/debug). Não roda automaticamente no startup.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';

class VendaItemMigrationService {
  /// Resultado agregado de uma execução da migração para uma loja.
  static const tagMigration = 'VENDA_ITEM_MIGRATION';
  static const tagMatch = 'VENDA_ITEM_MATCH';
  static const tagAmbiguo = 'VENDA_ITEM_AMBIGUO';
  static const tagSkip = 'VENDA_ITEM_SKIP';

  /// Executa a migração para uma loja. Retorna quantidade de vendas que tiveram
  /// pelo menos um item atualizado com productId.
  ///
  /// [lojaId] obrigatório. Abre vendas_lojaId e produtos_lojaId.
  /// Não altera nada além de productId nos itens; salva a venda só se houve alteração.
  static Future<VendaItemMigrationResult> migrarLoja(String lojaId) async {
    int vendasProcessadas = 0;
    int vendasAlteradas = 0;
    int itensMigrados = 0;
    int itensJaComId = 0;
    int itensSemMatch = 0;
    int itensAmbiguos = 0;

    if (lojaId.trim().isEmpty) {
      debugPrint('[$tagSkip] [$tagMigration] lojaId vazio, abortando');
      return VendaItemMigrationResult(
        lojaId: lojaId,
        vendasProcessadas: 0,
        vendasAlteradas: 0,
        itensMigrados: 0,
        itensJaComId: 0,
        itensSemMatch: 0,
        itensAmbiguos: 0,
      );
    }

    Box<Venda>• vendasBox;
    Box<Produto>• produtosBox;

    try {
      vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
    } catch (e, st) {
      debugPrint('[$tagMigration] Erro ao abrir boxes | lojaId=$lojaId | error=$e');
      if (kDebugMode) debugPrint(st.toString());
      return VendaItemMigrationResult(
        lojaId: lojaId,
        vendasProcessadas: 0,
        vendasAlteradas: 0,
        itensMigrados: 0,
        itensJaComId: 0,
        itensSemMatch: 0,
        itensAmbiguos: 0,
      );
    }

    final produtos = produtosBox.values.toList();
    debugPrint('[$tagMigration] Iniciando migração | lojaId=$lojaId | vendas=${vendasBox.length} | produtos=${produtos.length}');

    for (final venda in vendasBox.values) {
      final itens = venda.itens ?• [];
      if (itens.isEmpty) continue;

      vendasProcessadas++;
      bool vendaAlterada = false;
      final vendaId = venda.idFirebase ?• venda.key?.toString() ?• '';

      for (final item in itens) {
        if (_jaPossuiProductId(item)) {
          itensJaComId++;
          debugPrint('[$tagMigration] Item já possui productId | lojaId=$lojaId | vendaId=$vendaId | produtoNome=${item.produtoNome}');
          continue;
        }

        final nomeNorm = item.produtoNome.trim();
        if (nomeNorm.isEmpty) {
          itensSemMatch++;
          debugPrint('[$tagSkip] [$tagMigration] Nome vazio | lojaId=$lojaId | vendaId=$vendaId');
          continue;
        }

        final candidatos = _produtosComNomeExato(produtos, nomeNorm);
        if (candidatos.isEmpty) {
          itensSemMatch++;
          debugPrint('[$tagSkip] [$tagMigration] Nenhum match | lojaId=$lojaId | vendaId=$vendaId | produtoNome=$nomeNorm');
          continue;
        }
        if (candidatos.length > 1) {
          itensAmbiguos++;
          debugPrint('[$tagAmbiguo] [$tagMigration] Múltiplos matches | lojaId=$lojaId | vendaId=$vendaId | produtoNome=$nomeNorm | qtd=${candidatos.length}');
          continue;
        }

        final produto = candidatos.single;
        final idFirebase = produto.idFirebase.trim();
        if (idFirebase.isEmpty) {
          itensSemMatch++;
          debugPrint('[$tagSkip] [$tagMigration] Produto sem idFirebase | lojaId=$lojaId | produtoNome=$nomeNorm');
          continue;
        }

        item.productId = idFirebase;
        vendaAlterada = true;
        itensMigrados++;
        debugPrint('[$tagMatch] [$tagMigration] Migrado | lojaId=$lojaId | vendaId=$vendaId | produtoNome=$nomeNorm | productId=$idFirebase');
      }

      if (vendaAlterada) {
        vendasAlteradas++;
        await venda.save();
      }
    }

    debugPrint('[$tagMigration] Fim | lojaId=$lojaId | vendasAlteradas=$vendasAlteradas | itensMigrados=$itensMigrados | itensJaComId=$itensJaComId | itensSemMatch=$itensSemMatch | itensAmbiguos=$itensAmbiguos');
    return VendaItemMigrationResult(
      lojaId: lojaId,
      vendasProcessadas: vendasProcessadas,
      vendasAlteradas: vendasAlteradas,
      itensMigrados: itensMigrados,
      itensJaComId: itensJaComId,
      itensSemMatch: itensSemMatch,
      itensAmbiguos: itensAmbiguos,
    );
  }

  static bool _jaPossuiProductId(VendaItem item) {
    final id = item.productId;
    return id != null && id.trim().isNotEmpty;
  }

  /// Igualdade exata de nome (trim). Sem contains, startsWith ou fuzzy.
  static List<Produto> _produtosComNomeExato(List<Produto> produtos, String nomeNorm) {
    return produtos.where((p) => p.nome.trim() == nomeNorm).toList();
  }
}

/// Resultado da migração para uma loja (para UI ou logs).
class VendaItemMigrationResult {
  final String lojaId;
  final int vendasProcessadas;
  final int vendasAlteradas;
  final int itensMigrados;
  final int itensJaComId;
  final int itensSemMatch;
  final int itensAmbiguos;

  const VendaItemMigrationResult({
    required this.lojaId,
    required this.vendasProcessadas,
    required this.vendasAlteradas,
    required this.itensMigrados,
    required this.itensJaComId,
    required this.itensSemMatch,
    required this.itensAmbiguos,
  });
}
