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
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../core/produto_variacao_extra.dart';
import '../models/produto.dart';
import 'firestore_paths.dart';
import 'produtos_firestore_service.dart';
import 'vendas_service.dart';
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
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

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
    required String operacao, // 'baixa' ou 'devolucao'
  }) async {
    const tag = '[ESTOQUE]';

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
    if (produto.estoquePorTamanho.isNotEmpty && tam.isEmpty) {
      final msg = 'O produto "${produto.nome}" possui estoque por tamanho. É obrigatório informar o TAMANHO.';
      debugPrint('$tag $msg');
      return EstoqueResult.erro(msg);
    }

    // 4) Determinar tipo de estoque e executar operação
    int estoqueAntes = 0;
    int estoqueDepois = 0;

    try {
      if (operacao == 'baixa') {
        // === BAIXA via transação Firestore (atômico) ===
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

        final mensagemSucesso =
            'Estoque baixado com sucesso: ${produto.nome} [$tam - $corTrim] - $estoqueAntes → $estoqueDepois';
        debugPrint('$tag $mensagemSucesso');
        debugPrint('$tag ========================================');

        return EstoqueResult.sucesso(
          mensagem: mensagemSucesso,
          estoqueAntes: estoqueAntes,
          estoqueDepois: estoqueDepois,
          produto: produto,
        );
      }

      // === DEVOLUÇÃO (mantém lógica original - não usa transação) ===
      if (produto.usaVariacoes && (tam.isNotEmpty || corTrim.isNotEmpty)) {
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

      await produto.save();
      debugPrint('$tag Produto salvo no Hive');

      final estoqueGeralCalculado = _calcularEstoqueGeral(produto);
      if (produto.quantidade != estoqueGeralCalculado) {
        debugPrint('$tag AVISO: Corrigindo inconsistência no estoque geral');
        produto.quantidade = estoqueGeralCalculado;
        await produto.save();
      }

      await _sincronizarComFirestore(produto, lojaId);

      final mensagemSucesso =
          'Estoque devolvido com sucesso: ${produto.nome} [$tam - $corTrim] - $estoqueAntes → $estoqueDepois';
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

          // Criar produto e salvar no Hive
          final produto = Produto(
            idFirebase: doc.id,
            nome: data['nome'] ?? '',
            custoReal: (data['custoReal'] as num?)?.toDouble() ?? 0.0,
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
      return data.map((key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0));
    }
    return {};
  }

  /// Sincroniza estoque após ajuste manual (UI) e retorna o resultado para feedback.
  /// Usa a mesma lógica de _sincronizarComFirestore (leitura remota, heurística de divergência, escrita).
  static Future<ResultadoAjusteEstoque> sincronizarAjusteManual(
    Produto produto,
    String lojaId,
  ) async {
    return _sincronizarComFirestore(produto, lojaId);
  }

  /// Sincroniza produto com Firestore
  static Future<ResultadoAjusteEstoque> _sincronizarComFirestore(
    Produto produto,
    String lojaId,
  ) async {
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
        updateData['variacoes'] = produto.variacoes;
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
          // Doc ausente, regra de segurança ou ID órfão: recria / alinha com Hive.
          try {
            await ProdutosFirestoreService.syncProduto(produto, lojaId: lojaId);
            persistiuRemoto = true;
            debugPrint('$tag syncProduto OK após falha no update parcial');
          } catch (e2) {
            debugPrint(
              '$tag Erro também em syncProduto (type=${e2.runtimeType})',
            );
          }
        }
      } else {
        // Sem idFirebase: único caminho confiável é documento completo na nuvem.
        try {
          await ProdutosFirestoreService.syncProduto(produto, lojaId: lojaId);
          persistiuRemoto = true;
          debugPrint('$tag Produto enviado ao Firestore (idFirebase atribuído)');
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
