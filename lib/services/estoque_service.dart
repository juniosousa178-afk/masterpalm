// lib/services/estoque_service.dart
//
// SERVIÇO CENTRALIZADO DE CONTROLE DE ESTOQUE
//
// Este serviço é responsável por todas as operações de estoque do sistema:
// - Baixa de estoque (vendas)
// - Devolução de estoque (cancelamentos)
// - Validação de disponibilidade
// - Sincronização com Firestore
//
// REGRA FUNDAMENTAL:
// O estoque geral (quantidade) SEMPRE deve ser a soma de todas as variações.
// Nunca pode existir inconsistência entre estoque geral, por tamanho e por cor.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../core/produto_custo_guard.dart';
import '../core/hive_box_names.dart';
import '../core/produto_stock_revision.dart';
import 'stock_catalog_backend_service.dart';
import '../core/produto_variacao_extra.dart';
import '../models/produto.dart';
import 'combo_kit_stock_service.dart';
import 'firestore_paths.dart';
import 'produto_exclusao_tombstone_service.dart';
import 'produtos_firestore_service.dart';
import 'vendas_service.dart';
import 'catalogo_web_apos_estoque_service.dart';
import 'venda_estoque_remoto_prep_service.dart';
import 'estoque_transaction_service.dart';

/// Resultado de uma operação de estoque
class EstoqueResult {
  final bool sucesso;
  final String mensagem;
  final int estoqueAntes;
  final int estoqueDepois;
  final Produto? produto;

  EstoqueResult({
    required this.sucesso,
    required this.mensagem,
    this.estoqueAntes = 0,
    this.estoqueDepois = 0,
    this.produto,
  });

  factory EstoqueResult.erro(String mensagem) {
    return EstoqueResult(sucesso: false, mensagem: mensagem);
  }

  factory EstoqueResult.sucesso({
    required String mensagem,
    required int estoqueAntes,
    required int estoqueDepois,
    Produto? produto,
  }) {
    return EstoqueResult(
      sucesso: true,
      mensagem: mensagem,
      estoqueAntes: estoqueAntes,
      estoqueDepois: estoqueDepois,
      produto: produto,
    );
  }
}

/// Resultado de um ajuste manual de estoque em Firestore.
enum ResultadoAjusteEstoque {
  sucesso,
  divergenciaDetectada,
  erro,
}

/// Serviço centralizado para controle de estoque
class EstoqueService {
  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  /// Hive: atualiza [Produto.updatedAt] após mutação de quantidade no ramo **devolução** de [atualizarEstoque].
  /// Mesmo critério do +/- na lista: se o sync remoto falhar ou atrasar, o pull não deve regredir com snapshot velho.
  @visibleForTesting
  static void touchProdutoUpdatedAtParaDevolucaoHive(Produto p) {
    p.updatedAt = DateTime.now();
  }

  /// Após ajuste manual no filho, recalibra só combos que referenciam esse [productId] (teto ou piso).
  static Future<void> _recalcularCombosDepoisAjusteManual({
    required String lojaId,
    required Box<Produto> produtosBox,
    required Produto produtoAlterado,
    required bool foiBaixa,
  }) async {
    final pid = produtoAlterado.idFirebase.trim();
    if (pid.isEmpty) {
      debugPrint('[ESTOQUE] [COMBO_SYNC] Sem idFirebase no produto ajustado; pulando recálculo de combo.');
      return;
    }
    try {
      if (foiBaixa) {
        await ComboKitStockService.aplicarTetoEstoqueComboAposBaixa(
          lojaId: lojaId,
          produtosBox: produtosBox,
          produtoIdsDebitadosNaVenda: {pid},
        );
      } else {
        await ComboKitStockService.aplicarPisoEstoqueComboAposDevolucao(
          lojaId: lojaId,
          produtosBox: produtosBox,
          produtoIdsQueAfetamCombo: {pid},
        );
      }
    } catch (e, st) {
      debugPrint(
        '[ESTOQUE] [COMBO_SYNC] Falha ao recalibrar combos após ajuste manual (type=${e.runtimeType}): $e',
      );
      debugPrint('$st');
    }
  }

  // ============================================================
  // FUNÇÃO PRINCIPAL: ATUALIZAR ESTOQUE
  // ============================================================

  /// Atualiza o estoque de um produto (baixa ou devolução).
  /// Ordem de resolução: 1) produtoId, 2) produtoSlug, 3) produtoNome.
  ///
  /// [produtoId] - idFirebase (opcional; quando existir evita fallback por texto)
  /// [produtoSlug] - Slug (fallback)
  /// [produtoNome] - Nome (fallback)
  static Future<EstoqueResult> atualizarEstoque({
    required Box<Produto> produtosBox,
    required String lojaId,
    String? produtoId,
    String? produtoNome,
    String? produtoSlug,
    required String tamanho,
    required String cor,
    String variacaoExtra = '',
    required int quantidade,
    required String operacao, // 'baixa' | 'devolucao' | 'entrada_compra' | ...
  }) async {
    const tag = '[ESTOQUE]';

    if (!_isOperacaoBaixa(operacao) &&
        !_isOperacaoEstornoCompra(operacao) &&
        !_isOperacaoEntrada(operacao)) {
      return EstoqueResult.erro('Operação de estoque inválida: $operacao');
    }

    if (quantidade <= 0) {
      debugPrint('$tag ERRO: Quantidade deve ser maior que zero');
      return EstoqueResult.erro('Quantidade deve ser maior que zero');
    }

    if (produtoId == null || produtoId.isEmpty) {
      if (produtoNome == null && produtoSlug == null) {
        debugPrint('$tag ERRO: produtoId, nome ou slug do produto é obrigatório');
        return EstoqueResult.erro('ProdutoId, nome ou slug do produto é obrigatório');
      }
    }

    debugPrint('$tag ========================================');
    debugPrint('$tag Iniciando $operacao de estoque');
    debugPrint('$tag Produto: ${produtoId ?? produtoNome ?? produtoSlug}');
    debugPrint('$tag Tamanho: "${tamanho.isEmpty ? "VAZIO" : tamanho}"');
    debugPrint('$tag Cor: "${cor.isEmpty ? "VAZIO" : cor}"');
    debugPrint('$tag Quantidade: $quantidade');
    debugPrint('$tag LojaId: $lojaId');

    // 1) Buscar produto no Hive: productId primeiro, depois slug, depois nome
    Produto? produto = VendasService.encontrarProdutoNoEstoque(
      produtosBox: produtosBox,
      productId: (produtoId != null && produtoId.trim().isNotEmpty) ? produtoId.trim() : null,
      slug: produtoSlug,
      nome: produtoNome,
      lojaId: lojaId,
    );

    // 2) Se não encontrou no Hive, buscar no Firestore
    if (produto == null) {
      debugPrint('$tag Produto não encontrado no Hive, buscando no Firestore...');
      produto = await _buscarProdutoNoFirestore(
        lojaId: lojaId,
        nome: produtoNome,
        slug: produtoSlug,
        produtosBox: produtosBox,
      );
    }

    if (produto == null) {
      final msg = 'Produto não encontrado: ${produtoId ?? produtoNome ?? produtoSlug}';
      debugPrint('$tag ERRO: $msg');
      return EstoqueResult.erro(msg);
    }

    if (debugFirestoreOverride == null && hasPendingStockMutation(produto)) {
      return EstoqueResult.erro('Há um ajuste pendente neste produto. Sincronize antes de uma nova movimentação.');
    }

    debugPrint('$tag Produto encontrado: ${produto.nome}');
    debugPrint('$tag   - usaVariacoes: ${produto.usaVariacoes}');
    debugPrint('$tag   - variacoes: ${produto.variacoes}');
    debugPrint('$tag   - estoquePorTamanho: ${produto.estoquePorTamanho}');
    debugPrint('$tag   - quantidade atual: ${produto.quantidade}');

    // 3) Validar se produto usa variações
    final tam = tamanho.trim();
    final corTrim = cor.trim();
    final extraTrim = variacaoExtra.trim();

    // REGRA: Exigir conforme o tipo de variação do produto
    if (produto.temVariacaoSoloCor && corTrim.isEmpty) {
      final msg = 'O produto "${produto.nome}" possui variação de cor. É obrigatório informar a COR.';
      debugPrint('$tag $msg');
      return EstoqueResult.erro(msg);
    }
    if (produto.temVariacaoTamanhoECor && (tam.isEmpty || corTrim.isEmpty)) {
      final msg = 'O produto "${produto.nome}" possui variações de tamanho e cor. '
          'É obrigatório informar TAMANHO e COR.';
      debugPrint('$tag $msg');
      return EstoqueResult.erro(msg);
    }
    if (produto.temVariacaoSoloTamanho && tam.isEmpty && !produto.temVariacaoSoloCor) {
      final msg = 'O produto "${produto.nome}" possui variação de tamanho. É obrigatório informar o TAMANHO.';
      debugPrint('$tag $msg');
      return EstoqueResult.erro(msg);
    }
    if (produto.temEstoquePorTamanhoComTamanhoReal &&
        tam.isEmpty &&
        !produto.temVariacaoSoloCor) {
      final msg = 'O produto "${produto.nome}" possui estoque por tamanho. É obrigatório informar o TAMANHO.';
      debugPrint('$tag $msg');
      return EstoqueResult.erro(msg);
    }

    // 4) Determinar tipo de estoque e executar operação
    int estoqueAntes = 0;
    int estoqueDepois = 0;

    try {
      if (_isOperacaoBaixa(operacao) || _isOperacaoEstornoCompra(operacao)) {
        // === BAIXA / ESTORNO COMPRA via transação Firestore (atômico) ===
        final produtoId = produto.idFirebase.isNotEmpty ? produto.idFirebase : null;
        final result = await EstoqueTransactionService.baixarEstoqueTransaction(
          lojaId: lojaId,
          quantidade: quantidade,
          produtoId: produtoId,
          slug: produto.slug,
          nome: produto.nome,
          tamanho: tam,
          cor: corTrim,
          variacaoExtra: extraTrim,
        );

        estoqueAntes = result.quantidadeTotalAtualizada + result.quantidadeDebitada;
        estoqueDepois = result.quantidadeTotalAtualizada;

        await EstoqueTransactionService.atualizarHiveAposTransacao(
          produtosBox: produtosBox,
          lojaId: lojaId,
          result: result,
          tamanho: tam,
          cor: corTrim,
        );

        if (result.quantidadeDebitada > 0) {
          await _recalcularCombosDepoisAjusteManual(
            lojaId: lojaId,
            produtosBox: produtosBox,
            produtoAlterado: produto,
            foiBaixa: true,
          );
        }

        await CatalogoWebAposEstoqueService.sincronizarCatalogoWebAposMudancaEstoque(
          lojaId: lojaId,
          productIdsAfetados: {result.produtoId.trim()},
          produtosBox: produtosBox,
        );

        final mensagemSucesso = operacao == 'estorno_item_compra'
            ? 'Estorno de item de compra aplicado: ${produto.nome} [$tam - $corTrim] - $estoqueAntes → $estoqueDepois'
            : _isOperacaoEstornoCompra(operacao)
                ? 'Estorno de compra aplicado: ${produto.nome} [$tam - $corTrim] - $estoqueAntes → $estoqueDepois'
                : 'Estoque baixado com sucesso: ${produto.nome} [$tam - $corTrim] - $estoqueAntes → $estoqueDepois';
        debugPrint('$tag $mensagemSucesso');
        debugPrint('$tag ========================================');

        return EstoqueResult.sucesso(
          mensagem: mensagemSucesso,
          estoqueAntes: estoqueAntes,
          estoqueDepois: estoqueDepois,
          produto: produto,
        );
      }

      // === ENTRADA (devolução de venda, compra, ajuste+) — não usa transação ===
      final entradaComGradeInformada =
          _isOperacaoEntrada(operacao) && (tam.isNotEmpty || corTrim.isNotEmpty);
      if ((produto.usaVariacoes || entradaComGradeInformada) &&
          (tam.isNotEmpty || corTrim.isNotEmpty)) {
        produto.variacoes ??= <String, dynamic>{};
        final tamKey = tam.isEmpty ? '' : tam;
        final corKey = corTrim.isEmpty ? 'sem-cor' : corTrim;
        estoqueAntes = produto.obterEstoqueVariacao(tamKey, corKey, extraTrim);
        debugPrint('$tag Tipo: VARIAÇÃO');
        debugPrint('$tag Estoque ANTES: $estoqueAntes (${tam.isEmpty ? "cor" : tam}${corTrim.isEmpty ? "" : " - $corTrim"})');

        produto.devolverEstoqueVariacao(tamKey, corKey, quantidade, extraTrim);
        estoqueDepois = produto.obterEstoqueVariacao(tamKey, corKey, extraTrim);
        debugPrint('$tag Estoque DEPOIS: $estoqueDepois');
      } else if (produto.estoquePorTamanho.isNotEmpty && tam.isNotEmpty) {
        estoqueAntes = produto.estoquePorTamanho[tam] ?? 0;
        debugPrint('$tag Tipo: ESTOQUE POR TAMANHO');
        debugPrint('$tag Estoque ANTES: $estoqueAntes (tamanho $tam)');

        produto.devolverEstoquePorTamanho(tam, quantidade);
        estoqueDepois = produto.estoquePorTamanho[tam] ?? 0;
        debugPrint('$tag Estoque DEPOIS: $estoqueDepois (tamanho $tam)');
      } else {
        estoqueAntes = produto.quantidade;
        debugPrint('$tag Tipo: ESTOQUE TOTAL (sem variações)');
        debugPrint('$tag Estoque ANTES: $estoqueAntes');

        produto.quantidade += quantidade;
        estoqueDepois = produto.quantidade;
        debugPrint('$tag Estoque DEPOIS: $estoqueDepois');
      }

      touchProdutoUpdatedAtParaDevolucaoHive(produto);
      await produto.save();
      debugPrint('$tag Produto salvo no Hive');

      final estoqueGeralCalculado = _calcularEstoqueGeral(produto);
      if (produto.quantidade != estoqueGeralCalculado) {
        debugPrint('$tag AVISO: Corrigindo inconsistência no estoque geral');
        produto.quantidade = estoqueGeralCalculado;
        touchProdutoUpdatedAtParaDevolucaoHive(produto);
        await produto.save();
      }

      final syncResult = await _sincronizarComFirestore(produto, lojaId);
      if (syncResult == ResultadoAjusteEstoque.erro && debugFirestoreOverride == null) {
        return EstoqueResult.erro('A entrada está pendente de confirmação no servidor. Sincronize antes de repetir.');
      }

      if (estoqueDepois != estoqueAntes) {
        await _recalcularCombosDepoisAjusteManual(
          lojaId: lojaId,
          produtosBox: produtosBox,
          produtoAlterado: produto,
          foiBaixa: false,
        );
      }

      final pidDev = produto.idFirebase.trim();
      if (pidDev.isNotEmpty) {
        await CatalogoWebAposEstoqueService.sincronizarCatalogoWebAposMudancaEstoque(
          lojaId: lojaId,
          productIdsAfetados: {pidDev},
          produtosBox: produtosBox,
        );
      }

      final mensagemSucesso = _mensagemSucessoEntrada(
        operacao: operacao,
        nome: produto.nome,
        tam: tam,
        cor: corTrim,
        antes: estoqueAntes,
        depois: estoqueDepois,
      );
      debugPrint('$tag $mensagemSucesso');
      debugPrint('$tag ========================================');

      return EstoqueResult.sucesso(
        mensagem: mensagemSucesso,
        estoqueAntes: estoqueAntes,
        estoqueDepois: estoqueDepois,
        produto: produto,
      );
    } catch (e) {
      final msg = 'Erro ao atualizar estoque: $e';
      debugPrint('$tag ERRO: $msg');
      return EstoqueResult.erro(msg);
    }
  }

  static bool _isOperacaoBaixa(String operacao) => operacao == 'baixa';

  static bool _isOperacaoEstornoCompra(String operacao) =>
      operacao == 'estorno_compra' ||
      operacao == 'estorno_item_compra' ||
      operacao == 'cancelamento_compra';

  /// Entradas de estoque (soma quantidade). `devolucao` = legado (devolução de venda).
  static bool _isOperacaoEntrada(String operacao) {
    switch (operacao) {
      case 'devolucao':
      case 'entrada_compra':
      case 'entrada_estoque':
      case 'compra_revenda':
        return true;
      default:
        return false;
    }
  }

  static String _mensagemSucessoEntrada({
    required String operacao,
    required String nome,
    required String tam,
    required String cor,
    required int antes,
    required int depois,
  }) {
    final grade = (tam.isNotEmpty || cor.isNotEmpty) ? ' [$tam - $cor]' : '';
    final delta = '$antes → $depois';
    switch (operacao) {
      case 'entrada_compra':
      case 'compra_revenda':
        return 'Entrada de compra registrada: $nome$grade — $delta';
      case 'entrada_estoque':
        return 'Entrada de estoque registrada: $nome$grade — $delta';
      default:
        return 'Estoque devolvido com sucesso: $nome$grade — $delta';
    }
  }

  // ============================================================
  // FUNÇÃO SIMPLIFICADA PARA BAIXA DE ESTOQUE
  // ============================================================

  /// Baixa o estoque de um produto (versão simplificada)
  ///
  /// Esta é a função principal que deve ser usada em todos os fluxos de venda.
  /// Ela garante:
  /// - Validação de variações obrigatórias
  /// - Verificação de estoque suficiente
  /// - Baixa correta da variação específica
  /// - Recálculo do estoque geral
  /// - Sincronização com Firestore
  static Future<EstoqueResult> baixarEstoque({
    required Box<Produto> produtosBox,
    required String lojaId,
    String? produtoNome,
    String? produtoSlug,
    required String tamanho,
    required String cor,
    String variacaoExtra = '',
    required int quantidadeVendida,
  }) {
    return atualizarEstoque(
      produtosBox: produtosBox,
      lojaId: lojaId,
      produtoNome: produtoNome,
      produtoSlug: produtoSlug,
      tamanho: tamanho,
      cor: cor,
      variacaoExtra: variacaoExtra,
      quantidade: quantidadeVendida,
      operacao: 'baixa',
    );
  }

  // ============================================================
  // FUNÇÃO SIMPLIFICADA PARA DEVOLUÇÃO DE ESTOQUE
  // ============================================================

  /// Devolve o estoque de um produto (usado ao cancelar vendas)
  static Future<EstoqueResult> devolverEstoque({
    required Box<Produto> produtosBox,
    required String lojaId,
    String? produtoNome,
    String? produtoSlug,
    required String tamanho,
    required String cor,
    String variacaoExtra = '',
    required int quantidadeDevolvida,
  }) {
    return atualizarEstoque(
      produtosBox: produtosBox,
      lojaId: lojaId,
      produtoNome: produtoNome,
      produtoSlug: produtoSlug,
      tamanho: tamanho,
      cor: cor,
      variacaoExtra: variacaoExtra,
      quantidade: quantidadeDevolvida,
      operacao: 'devolucao',
    );
  }

  // ============================================================
  // VALIDAÇÃO DE ESTOQUE (SEM BAIXAR)
  // ============================================================

  /// Valida se há estoque disponível para uma venda (SEM baixar)
  ///
  /// Retorna [EstoqueResult] com sucesso se há estoque, erro se não há
  static Future<EstoqueResult> validarDisponibilidade({
    required Box<Produto> produtosBox,
    required String lojaId,
    String? produtoNome,
    String? produtoSlug,
    required String tamanho,
    required String cor,
    String variacaoExtra = '',
    required int quantidadeSolicitada,
  }) async {
    const tag = '[ESTOQUE-VALIDAR]';

    debugPrint('$tag Validando disponibilidade...');
    debugPrint('$tag Produto: ${produtoNome ?? produtoSlug}');
    debugPrint('$tag Tamanho: $tamanho, Cor: $cor, Qtd: $quantidadeSolicitada');

    // Buscar produto
    Produto? produto;

    if (produtoSlug != null && produtoSlug.isNotEmpty) {
      produto = VendasService.encontrarProdutoNoEstoque(
        produtosBox: produtosBox,
        slug: produtoSlug,
        lojaId: lojaId,
      );
    }

    if (produto == null && produtoNome != null && produtoNome.isNotEmpty) {
      produto = VendasService.encontrarProdutoNoEstoque(
        produtosBox: produtosBox,
        nome: produtoNome,
        lojaId: lojaId,
      );
    }

    produto ??= await _buscarProdutoNoFirestore(
        lojaId: lojaId,
        nome: produtoNome,
        slug: produtoSlug,
        produtosBox: produtosBox,
      );

    if (produto == null) {
      return EstoqueResult.erro('Produto não encontrado: ${produtoNome ?? produtoSlug}');
    }

    final tam = tamanho.trim();
    final corTrim = cor.trim();
    final extraTrim = variacaoExtra.trim();

    // Validar variações obrigatórias
    if (produto.usaVariacoes && (tam.isEmpty || corTrim.isEmpty)) {
      return EstoqueResult.erro(
        'O produto "${produto.nome}" possui variações. '
        'É obrigatório informar TAMANHO e COR. '
        'Tamanho: "${tam.isEmpty ? "VAZIO" : tam}", '
        'Cor: "${corTrim.isEmpty ? "VAZIO" : corTrim}".'
      );
    }

    // Verificar disponibilidade
    int disponivel;

    if (produto.usaVariacoes && tam.isNotEmpty && corTrim.isNotEmpty) {
      disponivel = produto.obterEstoqueVariacao(tam, corTrim, extraTrim);
    } else if (produto.estoquePorTamanho.isNotEmpty && tam.isNotEmpty) {
      disponivel = produto.estoquePorTamanho[tam] ?? 0;
    } else {
      disponivel = produto.quantidade;
    }

    debugPrint('$tag Disponível: $disponivel, Solicitado: $quantidadeSolicitada');

    if (disponivel < quantidadeSolicitada) {
      return EstoqueResult.erro(
        'Estoque insuficiente para "${produto.nome}". '
        'Disponível: $disponivel, solicitado: $quantidadeSolicitada.'
      );
    }

    return EstoqueResult.sucesso(
      mensagem: 'Estoque disponível',
      estoqueAntes: disponivel,
      estoqueDepois: disponivel - quantidadeSolicitada,
      produto: produto,
    );
  }

  // ============================================================
  // FUNÇÕES AUXILIARES
  // ============================================================

  /// Calcula o estoque geral com base nas variações
  static int _calcularEstoqueGeral(Produto produto) {
    if (produto.usaVariacoes && produto.variacoes != null) {
      // Somar todas as variações
      int total = 0;
      for (final mapaTamanho in produto.variacoes!.values) {
        if (mapaTamanho is Map) {
          for (final qtd in mapaTamanho.values) {
            total += ProdutoVariacaoExtra.somarCelula(qtd);
          }
        }
      }
      return total;
    } else if (produto.estoquePorTamanho.isNotEmpty) {
      // Somar estoque por tamanho
      int total = 0;
      for (final qtd in produto.estoquePorTamanho.values) {
        total += qtd;
      }
      return total;
    } else {
      // Retornar quantidade atual
      return produto.quantidade;
    }
  }

  /// Busca produto no Firestore e salva no Hive
  static Future<Produto?> _buscarProdutoNoFirestore({
    required String lojaId,
    String? nome,
    String? slug,
    required Box<Produto> produtosBox,
  }) async {
    try {
      final QuerySnapshot snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('produtos')
          .limit(500)
          .get();

      debugPrint('[ESTOQUE] Buscando no Firestore: ${snapshot.docs.length} produtos encontrados');

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final docSlug = (data['slug'] ?? '').toString().trim().toLowerCase();
        final docNome = (data['nome'] ?? '').toString().trim().toLowerCase();

        final slugMatch = slug != null && slug.isNotEmpty && docSlug == slug.trim().toLowerCase();
        final nomeMatch = nome != null && nome.isNotEmpty && docNome == nome.trim().toLowerCase();

        if (slugMatch || nomeMatch) {
          debugPrint('[ESTOQUE] Produto encontrado no Firestore: ${data['nome']}');

          for (final p in produtosBox.values) {
            if (p.lojaId != lojaId) continue;
            final idMatch = p.idFirebase == doc.id;
            final slugLocal = p.slug.trim().toLowerCase();
            final slugDoc = docSlug;
            if (idMatch || (slugLocal.isNotEmpty && slugLocal == slugDoc)) {
              p.nome = data['nome'] ?? p.nome;
              p.quantidade = (data['quantidade'] as num?)?.toInt() ?? p.quantidade;
              p.precoFinal =
                  (data['preco'] as num?)?.toDouble() ?? p.precoFinal;
              p.precoUnitario = (data['precoUnitario'] as num?)?.toDouble() ??
                  (data['preco'] as num?)?.toDouble() ??
                  p.precoUnitario;
              ProdutoCustoGuard.applyRemoteCustoOnExistingProduct(
                local: p,
                remoteData: data,
                logContext: 'estoque_catalogo_publico',
              );
              if (p.idFirebase.isEmpty) {
                p.idFirebase = doc.id;
              }
              await p.save();
              debugPrint(
                '[ESTOQUE] Produto catálogo público mesclado no Hive (custo preservado se aplicável)',
              );
              return p;
            }
          }

          // Criar produto e salvar no Hive (doc público sem custo → 0 inicial, não sobrescreve existente acima)
          final produto = Produto(
            idFirebase: doc.id,
            nome: data['nome'] ?? '',
            custoReal: ProdutoCustoGuard.custoInicialFromRemoteDoc(data),
            frete: 0.0,
            gastosFixos: 0.0,
            gastosVariaveis: 0.0,
            precoSugerido: (data['preco'] as num?)?.toDouble() ?? 0.0,
            precoFinal: (data['preco'] as num?)?.toDouble() ?? 0.0,
            precoUnitario: (data['precoUnitario'] as num?)?.toDouble() ?? (data['preco'] as num?)?.toDouble() ?? 0.0,
            quantidade: (data['quantidade'] as num?)?.toInt() ?? 0,
            categoria: data['categoria'] ?? '',
            dataEntrada: DateTime.now(),
            slug: data['slug'] ?? '',
            lojaId: lojaId,
            descricao: data['descricao'] ?? '',
            imagens: (data['imagens'] as List?)?.cast<String>() ?? [],
            tamanhos: (data['tamanhos'] as List?)?.cast<String>() ?? [],
            cores: (data['cores'] as List?)?.cast<String>() ?? [],
            estoquePorTamanho: _parseEstoquePorTamanho(data['estoquePorTamanho']),
            variacoes: data['variacoes'] as Map<String, dynamic>?,
            publicadoNoCatalogo: data['publicadoNoCatalogo'] ?? false,
          );

          // Salvar no Hive para próximas consultas
          await produtosBox.put(produto.idFirebase, produto);
          debugPrint('[ESTOQUE] Produto sincronizado do Firestore para Hive');

          return produto;
        }
      }

      return null;
    } catch (e) {
      debugPrint('[ESTOQUE] Erro ao buscar no Firestore (type=${e.runtimeType})');
      return null;
    }
  }

  /// Converte estoquePorTamanho do Firestore para Map<String, int>
  static Map<String, int> _parseEstoquePorTamanho(dynamic data) {
    if (data == null) return {};
    if (data is Map<String, int>) return data;
    if (data is Map) {
      return data.map(
        (key, value) => MapEntry(
          key.toString(),
          ProdutoVariacaoExtra.valorFirestoreComoInt(value),
        ),
      );
    }
    return {};
  }

  /// Sincroniza estoque após ajuste manual (UI) e retorna o resultado para feedback.
  /// Usa a mesma lógica de _sincronizarComFirestore (leitura remota, heurística de divergência, escrita).
  static Future<ResultadoAjusteEstoque> sincronizarAjusteManual(
    Produto produto,
    String lojaId,
  ) async {
    ensurePendingFlushWired();
    return _sincronizarComFirestore(produto, lojaId);
  }

  /// Liga o auto-flush de pendência usado pela prep de venda (evita ciclo de imports).
  static void ensurePendingFlushWired() {
    VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl ??=
        (lojaId, produto) async {
      final result = await sincronizarAjusteManual(produto, lojaId);
      if (result == ResultadoAjusteEstoque.sucesso ||
          result == ResultadoAjusteEstoque.divergenciaDetectada) {
        return !hasPendingStockMutation(produto);
      }
      // Falha de envio: ainda pode ser STALE se remoto avançou.
      return false;
    };
  }

  /// Reenvia mutações locais pendentes (produto-scoped ou loja inteira).
  /// Idempotente: reutiliza [pendingStockOperationId] existente.
  static Future<int> flushPendingStockMutations({
    required String lojaId,
    Box<Produto>? produtosBox,
    Iterable<Produto>? onlyProducts,
  }) async {
    ensurePendingFlushWired();
    final li = lojaId.trim();
    if (li.isEmpty) return 0;

    final targets = <Produto>[];
    if (onlyProducts != null) {
      for (final p in onlyProducts) {
        if (hasPendingStockMutation(p)) targets.add(p);
      }
    } else {
      final box = produtosBox ??
          (Hive.isBoxOpen(HiveBoxNames.produtos(li))
              ? Hive.box<Produto>(HiveBoxNames.produtos(li))
              : null);
      if (box == null) return 0;
      for (final p in box.values) {
        if (p.lojaId.trim().isNotEmpty && p.lojaId.trim() != li) continue;
        if (hasPendingStockMutation(p)) targets.add(p);
      }
    }

    var cleared = 0;
    for (final p in targets) {
      if (p.idFirebase.trim().isEmpty) continue;
      try {
        final result = await sincronizarAjusteManual(p, li);
        if ((result == ResultadoAjusteEstoque.sucesso ||
                result == ResultadoAjusteEstoque.divergenciaDetectada) &&
            !hasPendingStockMutation(p)) {
          cleared++;
          continue;
        }
        // Tentativa de reconcile stale após falha (ex.: failed-precondition).
        final ready =
            await VendaEstoqueRemotoPrepService.reconcilePendingStockMutationForSale(
          lojaId: li,
          produto: p,
        );
        if (ready && !hasPendingStockMutation(p)) cleared++;
      } catch (e) {
        debugPrint(
          '[ESTOQUE-PENDING-FLUSH] falha produto=${p.idFirebase} type=${e.runtimeType}',
        );
        try {
          final ready = await VendaEstoqueRemotoPrepService
              .reconcilePendingStockMutationForSale(lojaId: li, produto: p);
          if (ready && !hasPendingStockMutation(p)) cleared++;
        } catch (_) {}
      }
    }
    return cleared;
  }

  /// Interpreta resposta de `kind: replace` do stockCatalogCommand.
  static List<EstoqueTransactionResult> _resultadosReplaceDoBackend(
    Map<String, dynamic> response,
  ) {
    final rows = response['products'] as List? ?? const [];
    return rows.map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final grade = Map<String, dynamic>.from(row['variacoes'] as Map? ?? {});
      return EstoqueTransactionResult(
        produtoId: row['productId'] as String,
        produtoNome: (row['nome'] ?? '').toString(),
        produtoSlug: row['slug']?.toString(),
        quantidadeDebitada: 0,
        quantidadeTotalAtualizada: (row['quantidade'] as num).toInt(),
        variacoesAtualizadas: grade,
        estoquePorTamanhoAtualizado: (row['estoquePorTamanho'] as Map? ?? {})
            .map((key, units) =>
                MapEntry(key.toString(), (units as num).toInt())),
        newStockRevision: (row['stockRevision'] as num?)?.toInt(),
        stockOperationId:
            (row['stockOperationId'] ?? response['operationId'])?.toString(),
      );
    }).toList();
  }

  /// Aplica replace confirmado no Hive e limpa pending só com opId/revision remotos.
  static Future<void> _aplicarReplaceConfirmadoNoHive({
    required Box<Produto> produtosBox,
    required String lojaId,
    required EstoqueTransactionResult result,
  }) async {
    await EstoqueTransactionService.atualizarHiveAposTransacao(
      produtosBox: produtosBox,
      lojaId: lojaId,
      result: result,
    );
    // HEAD touch* re-marca pending; confirmar explicitamente após backend GREEN.
    Produto? produto;
    for (final p in produtosBox.values) {
      if (p.lojaId != lojaId) continue;
      if (result.produtoId.isNotEmpty && p.idFirebase == result.produtoId) {
        produto = p;
        break;
      }
    }
    if (produto == null) return;
    final op = result.stockOperationId?.trim();
    final rev = result.newStockRevision;
    if (op == null || op.isEmpty || rev == null) return;
    confirmStockMutation(produto, operationId: op, revision: rev);
    await produto.save();
  }

  /// Replace CAS com refresh de revisão em conflito (`aborted`) — 1 retry.
  static Future<ResultadoAjusteEstoque> _sincronizarAjusteViaBackendComRefreshCas({
    required Produto produto,
    required String lojaId,
  }) async {
    if (!hasPendingStockMutation(produto)) {
      markPendingStockMutation(
        produto,
        operationId: newStockOperationId(),
        baseRevision: produto.stockRevision,
      );
      await produto.save();
    }

    Future<Map<String, dynamic>> sendReplace({required String operationId, required int expectedRevision}) {
      return StockCatalogBackendService.command(
        lojaId: lojaId,
        operationId: operationId,
        kind: 'replace',
        items: [
          {
            'productId': produto.idFirebase,
            'expectedRevision': expectedRevision,
          }
        ],
        editorial: <String, dynamic>{},
        definition: {
          'quantidade': produto.quantidade,
          'tipoProduto': produto.tipoProduto,
          'variacoes': produto.variacoes == null
              ? null
              : ProdutoVariacaoExtra.sanitizeVariacoesMapForFirestore(
                  Map<String, dynamic>.from(produto.variacoes!),
                ),
          'estoquePorTamanho': produto.estoquePorTamanho,
          'tamanhos': produto.tamanhos,
          'cores': produto.cores,
          'variacoesExtraTipo':
              produto.variacoesExtraTipo ?? <String, dynamic>{},
          'itensCombo': produto.itensCombo ?? <Map<String, dynamic>>[],
          'comboConfig': produto.comboConfig,
        },
      );
    }

    try {
      final response = await sendReplace(
        operationId: produto.pendingStockOperationId!,
        expectedRevision:
            produto.pendingStockBaseRevision ?? produto.stockRevision,
      );
      final box = produto.box;
      if (box is! Box<Produto>) {
        throw StateError('Caixa de produtos indisponível.');
      }
      for (final result in _resultadosReplaceDoBackend(response)) {
        await _aplicarReplaceConfirmadoNoHive(
          produtosBox: box,
          lojaId: lojaId,
          result: result,
        );
      }
      return ResultadoAjusteEstoque.sucesso;
    } catch (error) {
      final code = error is FirebaseFunctionsException
          ? error.code
          : (error is FirebaseException ? error.code : '');
      final isCasConflict = code == 'aborted' ||
          (code == 'failed-precondition' &&
              (error.toString().toLowerCase().contains('revision') ||
                  error.toString().toLowerCase().contains('conflict')));
      if (!isCasConflict) rethrow;

      // Refresh remoto → rebases CAS → novo operationId → 1 retry.
      final snap = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produto.idFirebase)
          .get();
      if (!snap.exists) rethrow;
      final remote = snap.data() ?? <String, dynamic>{};
      final remoteRev = parseStockRevisionFromRemote(remote);
      final remoteQty = (remote['quantidade'] as num?)?.toInt() ?? 0;
      debugPrint(
        '[ESTOQUE-SYNC] CAS conflict — remoteRev=$remoteRev remoteQty=$remoteQty '
        'localPendingQty=${produto.quantidade}; refreshing base revision',
      );
      produto.stockRevision = remoteRev;
      markPendingStockMutation(
        produto,
        operationId: newStockOperationId(),
        baseRevision: remoteRev,
      );
      await produto.save();

      final retry = await sendReplace(
        operationId: produto.pendingStockOperationId!,
        expectedRevision: remoteRev,
      );
      final box = produto.box;
      if (box is! Box<Produto>) {
        throw StateError('Caixa de produtos indisponível.');
      }
      for (final result in _resultadosReplaceDoBackend(retry)) {
        await _aplicarReplaceConfirmadoNoHive(
          produtosBox: box,
          lojaId: lojaId,
          result: result,
        );
      }
      return ResultadoAjusteEstoque.sucesso;
    }
  }

  /// Sincroniza produto com Firestore
  static Future<ResultadoAjusteEstoque> _sincronizarComFirestore(
    Produto produto,
    String lojaId,
  ) async {
    if (debugFirestoreOverride == null) {
      if (produto.idFirebase.trim().isEmpty || !produto.isInBox) {
        return ResultadoAjusteEstoque.erro;
      }
      try {
        return await _sincronizarAjusteViaBackendComRefreshCas(
          produto: produto,
          lojaId: lojaId,
        );
      } catch (error, stack) {
        debugPrint('[ESTOQUE-SYNC] Comando de ajuste pendente: $error\n$stack');
        return ResultadoAjusteEstoque.erro;
      }
    }

    const tag = '[ESTOQUE-SYNC]';
    int? remoteQtd;
    bool divergenciaRelevante = false;

    try {
      // Fonte autoritativa de estoque é lojas/{lojaId}/estoque_produtos.
      // Baixas de venda devem passar por EstoqueTransactionService; este método é voltado a ajustes manuais.
      try {
        final snap = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(produto.idFirebase)
            .get();
        if (snap.exists) {
          final data = snap.data() ?? <String, dynamic>{};
          remoteQtd = (data['quantidade'] as num?)?.toInt();
          final localQtd = produto.quantidade;
          final diff = (remoteQtd != null) ? (remoteQtd - localQtd).abs() : null;

          debugPrint(
            '$tag [ESTOQUE_AJUSTE] Ajuste manual solicitado. lojaId=$lojaId, '
            'id=${produto.idFirebase}, remoto=$remoteQtd, local=$localQtd, diff=$diff',
          );

          if (remoteQtd != null && diff != null) {
            final bool limiarAbsoluto = diff >= 5;
            final bool limiarRelativo =
                remoteQtd != 0 && (diff / remoteQtd) >= 0.3;

            if (limiarAbsoluto || limiarRelativo) {
              divergenciaRelevante = true;
              debugPrint(
                '$tag [ESTOQUE_GUARD] Divergência relevante detectada. lojaId=$lojaId, '
                'id=${produto.idFirebase}, remoto=$remoteQtd, local=$localQtd, diff=$diff',
              );
            }
          }
        } else {
          debugPrint(
            '$tag [ESTOQUE] Ajuste manual: documento não existe em estoque_produtos. lojaId=$lojaId, id=${produto.idFirebase}',
          );
        }
      } catch (e) {
        debugPrint(
          '$tag [ESTOQUE] Falha ao ler estado remoto antes de ajuste manual (type=${e.runtimeType}) '
          '| lojaId=$lojaId | id=${produto.idFirebase}',
        );
      }

      final updateData = <String, dynamic>{
        'quantidade': produto.quantidade,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Adicionar variações se existirem
      if (produto.usaVariacoes && produto.variacoes != null) {
        updateData['variacoes'] =
            ProdutoVariacaoExtra.sanitizeVariacoesMapForFirestore(
          Map<String, dynamic>.from(produto.variacoes!),
        );
      }
      if (produto.estoquePorTamanho.isNotEmpty) {
        updateData['estoquePorTamanho'] = produto.estoquePorTamanho;
      }

      /// Garante persistência na nuvem: update parcial ou documento completo ([syncProduto]).
      var persistiuRemoto = false;

      Future<void> atualizarCatalogoParalelo() async {
        if (!produto.publicadoNoCatalogo) return;
        try {
          await _db
              .collection('lojas')
              .doc(lojaId)
              .collection('produtos')
              .doc(produto.idFirebase)
              .update(updateData);
          debugPrint(
            '$tag [ESTOQUE_WRITE] Atualizado produtos (catálogo): ${produto.idFirebase}',
          );
        } catch (e) {
          debugPrint(
            '$tag Erro ao atualizar catálogo (normal se não publicado) (type=${e.runtimeType})',
          );
        }
      }

      // Atualizar em estoque_produtos (ou criar doc completo se idFirebase vazio / update falhar)
      if (produto.idFirebase.isNotEmpty) {
        try {
          await _db
              .collection('lojas')
              .doc(lojaId)
              .collection(FSPaths.estoqueProdutosCol)
              .doc(produto.idFirebase)
              .update(updateData);
          debugPrint('$tag Atualizado estoque_produtos: ${produto.idFirebase}');
          persistiuRemoto = true;
          await atualizarCatalogoParalelo();
        } catch (e) {
          debugPrint(
            '$tag Erro ao atualizar estoque_produtos (type=${e.runtimeType}) — tentando syncProduto completo',
          );
          if (await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
            lojaId: lojaId,
            estoqueDocId: produto.idFirebase,
          )) {
            debugPrint(
              '$tag [DELETE_GUARD] recriação via syncProduto bloqueada (tombstone de exclusão)',
            );
            return ResultadoAjusteEstoque.erro;
          }
          // Doc ausente, regra de segurança ou ID órfão: recria / alinha com Hive.
          try {
            final status = await ProdutosFirestoreService.syncProdutoComStatus(
              produto,
              lojaId: lojaId,
              bumpHiveTimestamp: false,
              writeOrigin: 'estoque_service.fallback_sync',
              enqueueOnFailure: true,
            );
            persistiuRemoto = status == ProdutoSyncRemotoStatus.confirmado ||
                status == ProdutoSyncRemotoStatus.semMudancas;
            debugPrint(
              '$tag syncProduto após falha no update parcial: status=$status',
            );
          } catch (e2) {
            debugPrint(
              '$tag Erro também em syncProduto (type=${e2.runtimeType})',
            );
          }
        }
      } else {
        // Sem idFirebase: único caminho confiável é documento completo na nuvem.
        try {
          if (produto.slug.trim().isNotEmpty &&
              await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
                lojaId: lojaId,
                estoqueDocId: produto.slug.trim(),
              )) {
            debugPrint(
              '$tag [DELETE_GUARD] syncProduto bloqueado (tombstone) slug=${produto.slug}',
            );
            return ResultadoAjusteEstoque.erro;
          }
          final status = await ProdutosFirestoreService.syncProdutoComStatus(
            produto,
            lojaId: lojaId,
            bumpHiveTimestamp: false,
            writeOrigin: 'estoque_service.sem_id_firebase',
            enqueueOnFailure: true,
          );
          persistiuRemoto = status == ProdutoSyncRemotoStatus.confirmado ||
              status == ProdutoSyncRemotoStatus.semMudancas;
          debugPrint('$tag Produto enviado ao Firestore: status=$status');
        } catch (e) {
          debugPrint('$tag Erro ao sincronizar produto sem idFirebase (type=${e.runtimeType})');
        }
      }

      if (!persistiuRemoto) {
        return ResultadoAjusteEstoque.erro;
      }
      return divergenciaRelevante
          ? ResultadoAjusteEstoque.divergenciaDetectada
          : ResultadoAjusteEstoque.sucesso;
    } catch (e) {
      debugPrint('$tag Erro geral ao sincronizar (type=${e.runtimeType})');
      return ResultadoAjusteEstoque.erro;
    }
  }

  // ============================================================
  // UTILITÁRIOS
  // ============================================================

  /// Verifica se um produto tem variações configuradas
  static bool produtoTemVariacoes(Produto produto) {
    return produto.usaVariacoes ||
           (produto.variacoes != null && produto.variacoes!.isNotEmpty);
  }

  /// Verifica se um produto usa apenas tamanhos (sem cores)
  static bool produtoUsaApenasTamanhos(Produto produto) {
    return !produto.usaVariacoes && produto.estoquePorTamanho.isNotEmpty;
  }

  /// Obtém o estoque disponível para uma variação específica
  static int obterEstoqueDisponivel(
    Produto produto,
    String tamanho,
    String cor,
  ) {
    if (produto.usaVariacoes && tamanho.isNotEmpty && cor.isNotEmpty) {
      return produto.obterEstoqueVariacao(tamanho, cor);
    } else if (produto.estoquePorTamanho.isNotEmpty && tamanho.isNotEmpty) {
      return produto.estoquePorTamanho[tamanho] ?? 0;
    } else {
      return produto.quantidade;
    }
  }
}
