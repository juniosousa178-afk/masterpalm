// Importação Excel: resultado por linha e orquestração de sync.

import 'package:hive/hive.dart';

import '../core/produto_custo_guard.dart';
import '../core/produto_firestore_doc_id_validator.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import 'produto_upsert_service.dart';
import 'sync_queue_service.dart';

/// Estado mínimo de cada linha importada.
enum ProdutoImportLinhaStatus {
  importadoLocalmente,
  sincronizado,
  pendenteSincronizacao,
  falhouIdInvalido,
  falhouDadosInvalidos,
  bloqueadoTombstone,
  recuperacaoManualNecessaria,
  ignoradoConflito,
  atualizadoLocalmente,
}

class ProdutoImportLinhaResult {
  const ProdutoImportLinhaResult({
    required this.linha,
    required this.status,
    this.nome = '',
    this.produto,
  });

  final int linha;
  final ProdutoImportLinhaStatus status;
  final String nome;
  final Produto? produto;
}

class ProdutoImportResumo {
  const ProdutoImportResumo({required this.linhas});

  final List<ProdutoImportLinhaResult> linhas;

  int count(ProdutoImportLinhaStatus status) =>
      linhas.where((l) => l.status == status).length;

  int get importadosComSucessoLocal =>
      count(ProdutoImportLinhaStatus.importadoLocalmente) +
      count(ProdutoImportLinhaStatus.sincronizado) +
      count(ProdutoImportLinhaStatus.pendenteSincronizacao) +
      count(ProdutoImportLinhaStatus.atualizadoLocalmente);

  String mensagemResumo() {
    final sincronizados = count(ProdutoImportLinhaStatus.sincronizado);
    final pendentes = count(ProdutoImportLinhaStatus.pendenteSincronizacao);
    final falhas = count(ProdutoImportLinhaStatus.falhouIdInvalido) +
        count(ProdutoImportLinhaStatus.falhouDadosInvalidos) +
        count(ProdutoImportLinhaStatus.ignoradoConflito);
    final tombstone = count(ProdutoImportLinhaStatus.bloqueadoTombstone);
    final recuperacao =
        count(ProdutoImportLinhaStatus.recuperacaoManualNecessaria);
    final buf = StringBuffer('Importação concluída: ');
    buf.write('Importados com sucesso: $importadosComSucessoLocal');
    buf.write(' · Sincronizados: $sincronizados');
    if (pendentes > 0) buf.write(' · Pendentes de sincronização: $pendentes');
    if (falhas > 0) buf.write(' · Falharam: $falhas');
    if (tombstone > 0) buf.write(' · Bloqueados por tombstone: $tombstone');
    if (recuperacao > 0) {
      buf.write(' · Recuperação manual necessária: $recuperacao');
    }
    return buf.toString();
  }
}

class ProdutoImportService {
  ProdutoImportService._();

  /// Processa uma linha: upsert local offline + enfileira sync (sem Firestore).
  static Future<ProdutoImportLinhaResult> processarLinha({
    required int linha,
    required Produto produto,
    required String lojaId,
    required Box<Produto> produtosBox,
    required Box<Venda> vendasBox,
    String? codigoBarras,
    String? sku,
    ImportCustoInput importCusto = ImportCustoInput.colunaAusente,
  }) async {
    final nome = produto.nome.trim();
    if (nome.isEmpty) {
      return ProdutoImportLinhaResult(
        linha: linha,
        status: ProdutoImportLinhaStatus.falhouDadosInvalidos,
        nome: nome,
      );
    }

    produto.lojaId = lojaId;

    final (upsertResult, produtoAfetado) = await upsertProdutoParaImportacao(
      produtosBox,
      lojaId,
      produto,
      vendasBox,
      codigoBarras: codigoBarras,
      sku: sku,
      importCusto: importCusto,
    );

    switch (upsertResult) {
      case UpsertImportResult.skippedConflict:
        return ProdutoImportLinhaResult(
          linha: linha,
          status: ProdutoImportLinhaStatus.ignoradoConflito,
          nome: nome,
        );
      case UpsertImportResult.recuperacaoManualNecessaria:
        return ProdutoImportLinhaResult(
          linha: linha,
          status: ProdutoImportLinhaStatus.recuperacaoManualNecessaria,
          nome: nome,
          produto: produtoAfetado,
        );
      case UpsertImportResult.falhouIdInvalido:
        return ProdutoImportLinhaResult(
          linha: linha,
          status: ProdutoImportLinhaStatus.falhouIdInvalido,
          nome: nome,
        );
      case UpsertImportResult.inserted:
      case UpsertImportResult.updated:
        break;
    }

    final p = produtoAfetado;
    if (p == null) {
      return ProdutoImportLinhaResult(
        linha: linha,
        status: ProdutoImportLinhaStatus.falhouDadosInvalidos,
        nome: nome,
      );
    }

    final idCheck = ProdutoFirestoreDocIdValidator.validateProduto(
      storeId: lojaId,
      produto: p,
    );
    if (!idCheck.ok) {
      return ProdutoImportLinhaResult(
        linha: linha,
        status: ProdutoImportLinhaStatus.falhouIdInvalido,
        nome: nome,
        produto: p,
      );
    }

    final entityKey = p.key;
    if (entityKey == null) {
      return ProdutoImportLinhaResult(
        linha: linha,
        status: ProdutoImportLinhaStatus.falhouDadosInvalidos,
        nome: nome,
        produto: p,
      );
    }
    final parsedKey =
        entityKey is int ? entityKey : int.tryParse(entityKey.toString());
    if (parsedKey == null) {
      return ProdutoImportLinhaResult(
        linha: linha,
        status: ProdutoImportLinhaStatus.falhouIdInvalido,
        nome: nome,
        produto: p,
      );
    }

    await SyncQueueService.init();
    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: lojaId,
      boxName: produtosBox.name,
      entityKey: parsedKey,
    );

    return ProdutoImportLinhaResult(
      linha: linha,
      status: ProdutoImportLinhaStatus.pendenteSincronizacao,
      nome: nome,
      produto: p,
    );
  }
}
