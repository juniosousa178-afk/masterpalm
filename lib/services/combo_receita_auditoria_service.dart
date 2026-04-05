// lib/services/combo_receita_auditoria_service.dart
// Auditoria passiva de receitas de combo — somente leitura, sem persistência.

import 'dart:convert';

import '../models/produto.dart';
import 'combo_receita_normalizacao.dart';

/// Status por linha da receita (conforme especificação MasterPalm).
enum StatusLinhaReceitaAuditoria {
  okCanonico,
  semProductIdMasResolvivel,
  ambiguo,
  produtoNaoEncontrado,
  productIdInvalido,
  receitaLinhaInconsistente,
}

/// Status agregado do combo.
enum StatusComboAuditoria {
  ok,
  okComRessalvas,
  pendente,
  critico,
}

String _strLinha(StatusLinhaReceitaAuditoria s) {
  switch (s) {
    case StatusLinhaReceitaAuditoria.okCanonico:
      return 'OK_CANONICO';
    case StatusLinhaReceitaAuditoria.semProductIdMasResolvivel:
      return 'SEM_PRODUCT_ID_MAS_RESOLVIVEL';
    case StatusLinhaReceitaAuditoria.ambiguo:
      return 'AMBIGUO';
    case StatusLinhaReceitaAuditoria.produtoNaoEncontrado:
      return 'PRODUTO_NAO_ENCONTRADO';
    case StatusLinhaReceitaAuditoria.productIdInvalido:
      return 'PRODUCT_ID_INVALIDO';
    case StatusLinhaReceitaAuditoria.receitaLinhaInconsistente:
      return 'RECEITA_VAZIA_OU_INCONSISTENTE';
  }
}

String _strCombo(StatusComboAuditoria s) {
  switch (s) {
    case StatusComboAuditoria.ok:
      return 'OK';
    case StatusComboAuditoria.okComRessalvas:
      return 'OK_COM_RESSALVAS';
    case StatusComboAuditoria.pendente:
      return 'PENDENTE';
    case StatusComboAuditoria.critico:
      return 'CRITICO';
  }
}

/// Detalhe de um componente da receita.
class AuditoriaLinhaReceita {
  AuditoriaLinhaReceita({
    required this.indice,
    required this.nomeSalvo,
    required this.slugSalvo,
    required this.productIdSalvo,
    required this.quantidadeExigida,
    required this.status,
    this.produtoResolvidoNome,
    this.produtoResolvidoId,
    this.candidatosIds,
    this.candidatosNomes,
    required this.observacaoTecnica,
    required this.acaoRecomendada,
  });

  final int indice;
  final String nomeSalvo;
  final String slugSalvo;
  final String productIdSalvo;
  final int quantidadeExigida;
  final StatusLinhaReceitaAuditoria status;
  final String? produtoResolvidoNome;
  final String? produtoResolvidoId;
  final List<String>? candidatosIds;
  final List<String>? candidatosNomes;
  final String observacaoTecnica;
  final String acaoRecomendada;

  Map<String, dynamic> toJson() => {
        'indice': indice,
        'nomeSalvo': nomeSalvo,
        'slugSalvo': slugSalvo,
        'productIdSalvo': productIdSalvo,
        'quantidadeExigida': quantidadeExigida,
        'status': _strLinha(status),
        'produtoResolvidoNome': produtoResolvidoNome,
        'produtoResolvidoId': produtoResolvidoId,
        'candidatosIds': candidatosIds,
        'candidatosNomes': candidatosNomes,
        'observacaoTecnica': observacaoTecnica,
        'acaoRecomendada': acaoRecomendada,
      };
}

/// Resultado da auditoria de um combo.
class AuditoriaComboResultado {
  AuditoriaComboResultado({
    required this.nomeCombo,
    required this.productIdCombo,
    required this.slugCombo,
    required this.quantidadeItensReceita,
    required this.statusGeral,
    required this.linhas,
    required this.observacaoCombo,
    required this.acoesRecomendadasCombo,
  });

  final String nomeCombo;
  final String productIdCombo;
  final String slugCombo;
  final int quantidadeItensReceita;
  final StatusComboAuditoria statusGeral;
  final List<AuditoriaLinhaReceita> linhas;
  final String observacaoCombo;
  final List<String> acoesRecomendadasCombo;

  Map<String, dynamic> toJson() => {
        'nomeCombo': nomeCombo,
        'productIdCombo': productIdCombo,
        'slugCombo': slugCombo,
        'quantidadeItensReceita': quantidadeItensReceita,
        'statusGeral': _strCombo(statusGeral),
        'linhas': linhas.map((e) => e.toJson()).toList(),
        'observacaoCombo': observacaoCombo,
        'acoesRecomendadasCombo': acoesRecomendadasCombo,
      };
}

/// Resumo executivo.
class ResumoExecutivoAuditoriaCombos {
  ResumoExecutivoAuditoriaCombos({
    required this.lojaId,
    required this.totalCombosAnalisados,
    required this.totalCombos100PorcentoOk,
    required this.totalCombosComPendencia,
    required this.totalComponentesAuditados,
    required this.contagemPorStatusLinha,
  });

  final String lojaId;
  final int totalCombosAnalisados;
  final int totalCombos100PorcentoOk;
  final int totalCombosComPendencia;
  final int totalComponentesAuditados;
  final Map<String, int> contagemPorStatusLinha;

  Map<String, dynamic> toJson() => {
        'lojaId': lojaId,
        'totalCombosAnalisados': totalCombosAnalisados,
        'totalCombos100PorcentoOk': totalCombos100PorcentoOk,
        'totalCombosComPendencia': totalCombosComPendencia,
        'totalComponentesAuditados': totalComponentesAuditados,
        'contagemPorStatusLinha': contagemPorStatusLinha,
      };
}

/// Relatório completo (memória + serialização).
class RelatorioAuditoriaCombos {
  RelatorioAuditoriaCombos({
    required this.resumo,
    required this.combos,
  });

  final ResumoExecutivoAuditoriaCombos resumo;
  final List<AuditoriaComboResultado> combos;

  /// Ordem: CRITICO → PENDENTE → OK_COM_RESSALVAS → OK
  List<AuditoriaComboResultado> get rankingPorGravidade {
    int ordem(StatusComboAuditoria s) {
      switch (s) {
        case StatusComboAuditoria.critico:
          return 0;
        case StatusComboAuditoria.pendente:
          return 1;
        case StatusComboAuditoria.okComRessalvas:
          return 2;
        case StatusComboAuditoria.ok:
          return 3;
      }
    }

    final copia = List<AuditoriaComboResultado>.from(combos);
    copia.sort((a, b) => ordem(a.statusGeral).compareTo(ordem(b.statusGeral)));
    return copia;
  }

  Map<String, dynamic> toJson() => {
        'resumo': resumo.toJson(),
        'combos': combos.map((e) => e.toJson()).toList(),
        'rankingPorGravidade':
            rankingPorGravidade.map((e) => e.toJson()).toList(),
      };

  String comoJsonIndentado() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  /// Texto para console / log (somente diagnóstico).
  String comoTextoFormatado() {
    final sb = StringBuffer();
    sb.writeln('=== AUDITORIA PASSIVA DE COMBOS ===');
    sb.writeln('lojaId: ${resumo.lojaId}');
    sb.writeln('--- Resumo executivo ---');
    sb.writeln('Combos analisados: ${resumo.totalCombosAnalisados}');
    sb.writeln('Combos 100% OK: ${resumo.totalCombos100PorcentoOk}');
    sb.writeln('Combos com pendência: ${resumo.totalCombosComPendencia}');
    sb.writeln('Componentes auditados: ${resumo.totalComponentesAuditados}');
    sb.writeln('Por status de linha: ${resumo.contagemPorStatusLinha}');
    sb.writeln('--- Ranking por gravidade ---');
    for (final c in rankingPorGravidade) {
      sb.writeln('* ${_strCombo(c.statusGeral)} | ${c.nomeCombo} | itens=${c.quantidadeItensReceita}');
    }
    sb.writeln('--- Detalhe ---');
    for (final c in combos) {
      sb.writeln('');
      sb.writeln('[${_strCombo(c.statusGeral)}] ${c.nomeCombo}');
      sb.writeln('  combo productId=${c.productIdCombo} slug=${c.slugCombo}');
      sb.writeln('  ${c.observacaoCombo}');
      for (final a in c.acoesRecomendadasCombo) {
        sb.writeln('  → $a');
      }
      for (final linha in c.linhas) {
        sb.writeln(
          '  linha[${linha.indice}] ${_strLinha(linha.status)} | nome="${linha.nomeSalvo}" pid="${linha.productIdSalvo}" qtd=${linha.quantidadeExigida}',
        );
        if (linha.candidatosIds != null && linha.candidatosIds!.isNotEmpty) {
          sb.writeln('    candidatos: ${linha.candidatosNomes}');
        }
        sb.writeln('    ${linha.observacaoTecnica}');
        sb.writeln('    ação: ${linha.acaoRecomendada}');
      }
    }
    return sb.toString();
  }
}

/// Serviço de auditoria — **não persiste dados**.
class ComboReceitaAuditoriaService {
  ComboReceitaAuditoriaService._();

  static List<Produto> _combosDaLoja(String lojaId, Iterable<Produto> todos) {
    return todos
        .where((p) => p.lojaId == lojaId && p.ehCombo)
        .toList();
  }

  static List<Produto> _produtosNaoComboLoja(String lojaId, Iterable<Produto> todos) {
    return todos.where((p) => p.lojaId == lojaId && !p.ehCombo).toList();
  }

  static int _qtdExigida(Map<String, dynamic> m) {
    final q = m['quantidade'];
    if (q is num) return q.toInt().clamp(0, 999999);
    return int.tryParse(q?.toString() ?? '') ?? 0;
  }

  /// Classifica uma linha da receita (somente leitura).
  static AuditoriaLinhaReceita auditarLinha({
    required int indice,
    required Map<String, dynamic> raw,
    required List<Produto> produtosNaoCombo,
  }) {
    final nomeSalvo = (raw['nome'] ?? '').toString().trim();
    final slugSalvo = (raw['slug'] ?? '').toString().trim();
    final pid = ComboReceitaNormalizacao.pidFrom(raw);
    final qtd = _qtdExigida(raw);

    Produto? porId(String id) {
      for (final p in produtosNaoCombo) {
        if (p.idFirebase.trim() == id) return p;
      }
      return null;
    }

    if (pid.isNotEmpty) {
      final p = porId(pid);
      if (p != null) {
        return AuditoriaLinhaReceita(
          indice: indice,
          nomeSalvo: nomeSalvo,
          slugSalvo: slugSalvo,
          productIdSalvo: pid,
          quantidadeExigida: qtd,
          status: StatusLinhaReceitaAuditoria.okCanonico,
          produtoResolvidoNome: p.nome,
          produtoResolvidoId: p.idFirebase,
          observacaoTecnica:
              'productId referencia produto existente na loja; fluxos futuros podem usar ID sem fallback por nome.',
          acaoRecomendada: 'Nenhuma — componente canônico.',
        );
      }
      return AuditoriaLinhaReceita(
        indice: indice,
        nomeSalvo: nomeSalvo,
        slugSalvo: slugSalvo,
        productIdSalvo: pid,
        quantidadeExigida: qtd,
        status: StatusLinhaReceitaAuditoria.productIdInvalido,
        observacaoTecnica:
            'productId presente na receita mas não há produto com este idFirebase na loja (referência órfã).',
        acaoRecomendada:
            'Corrigir vínculo: reabrir o cadastro do combo e selecionar novamente o componente, ou sincronizar/importar o produto correspondente.',
      );
    }

    if (nomeSalvo.isEmpty && slugSalvo.isEmpty) {
      return AuditoriaLinhaReceita(
        indice: indice,
        nomeSalvo: nomeSalvo,
        slugSalvo: slugSalvo,
        productIdSalvo: pid,
        quantidadeExigida: qtd,
        status: StatusLinhaReceitaAuditoria.receitaLinhaInconsistente,
        observacaoTecnica:
            'Linha sem productId, nome e slug — malformada; fluxos que caírem em fallback por nome não têm âncora.',
        acaoRecomendada:
            'Remover linha inválida ou preencher selecionando o produto no cadastro do combo.',
      );
    }

    if (slugSalvo.isNotEmpty) {
      final porSlug =
          produtosNaoCombo.where((p) => p.slug.trim() == slugSalvo).toList();
      if (porSlug.length > 1) {
        return AuditoriaLinhaReceita(
          indice: indice,
          nomeSalvo: nomeSalvo,
          slugSalvo: slugSalvo,
          productIdSalvo: pid,
          quantidadeExigida: qtd,
          status: StatusLinhaReceitaAuditoria.ambiguo,
          candidatosIds: porSlug.map((e) => e.idFirebase).toList(),
          candidatosNomes: porSlug.map((e) => e.nome).toList(),
          observacaoTecnica:
              'Mais de um produto com o mesmo slug na loja — risco de associação errática se usar slug/nome como chave.',
          acaoRecomendada:
              'Corrigir item duplicado/ambíguo: garantir slugs únicos ou fixar productId canônico ao editar o combo.',
        );
      }
      if (porSlug.length == 1) {
        final p = porSlug.first;
        return AuditoriaLinhaReceita(
          indice: indice,
          nomeSalvo: nomeSalvo,
          slugSalvo: slugSalvo,
          productIdSalvo: pid,
          quantidadeExigida: qtd,
          status: StatusLinhaReceitaAuditoria.semProductIdMasResolvivel,
          produtoResolvidoNome: p.nome,
          produtoResolvidoId: p.idFirebase.isNotEmpty ? p.idFirebase : null,
          observacaoTecnica: p.idFirebase.trim().isEmpty
              ? 'Correspondência única por slug, mas o produto ainda não tem idFirebase — saneamento estrutural pendente.'
              : 'Correspondência única por slug; falta gravar productId na receita — possível fallback por nome em fluxos legados.',
          acaoRecomendada: p.idFirebase.trim().isEmpty
              ? 'Sincronizar produto antes de vincular; depois regravar o combo para fixar productId.'
              : 'Reabrir o combo e salvar para persistir productId do componente (ou edição equivalente).',
        );
      }
    }

    if (nomeSalvo.isEmpty) {
      return AuditoriaLinhaReceita(
        indice: indice,
        nomeSalvo: nomeSalvo,
        slugSalvo: slugSalvo,
        productIdSalvo: pid,
        quantidadeExigida: qtd,
        status: StatusLinhaReceitaAuditoria.produtoNaoEncontrado,
        observacaoTecnica:
            'Sem productId e sem nome para cruzamento; slug não casou com nenhum produto.',
        acaoRecomendada:
            'Selecionar o produto na lista do cadastro do combo ou corrigir slug.',
      );
    }

    final alvo = ComboReceitaNormalizacao.normalizarNomeComparacao(nomeSalvo);
    final porNome = produtosNaoCombo
        .where(
          (p) =>
              ComboReceitaNormalizacao.normalizarNomeComparacao(p.nome) ==
              alvo,
        )
        .toList();

    if (porNome.length > 1) {
      return AuditoriaLinhaReceita(
        indice: indice,
        nomeSalvo: nomeSalvo,
        slugSalvo: slugSalvo,
        productIdSalvo: pid,
        quantidadeExigida: qtd,
        status: StatusLinhaReceitaAuditoria.ambiguo,
        candidatosIds: porNome.map((e) => e.idFirebase).toList(),
        candidatosNomes: porNome.map((e) => e.nome).toList(),
        observacaoTecnica:
            'Vários produtos com o mesmo nome normalizado — homônimos; fallback por nome é inseguro.',
        acaoRecomendada:
            'Corrigir ambiguidade: renomear produtos ou fixar productId ao editar o combo.',
      );
    }
    if (porNome.length == 1) {
      final p = porNome.first;
      return AuditoriaLinhaReceita(
        indice: indice,
        nomeSalvo: nomeSalvo,
        slugSalvo: slugSalvo,
        productIdSalvo: pid,
        quantidadeExigida: qtd,
        status: StatusLinhaReceitaAuditoria.semProductIdMasResolvivel,
        produtoResolvidoNome: p.nome,
        produtoResolvidoId: p.idFirebase.isNotEmpty ? p.idFirebase : null,
        observacaoTecnica: p.idFirebase.trim().isEmpty
            ? 'Nome único na loja mas produto sem idFirebase.'
            : 'Nome único na loja — legado típico sem productId na receita; risco residual em fluxos que ainda casem por nome.',
        acaoRecomendada: p.idFirebase.trim().isEmpty
            ? 'Sincronizar produto antes de vincular; depois fixar productId na receita.'
            : 'Preencher productId do componente ao regravar o combo.',
      );
    }

    return AuditoriaLinhaReceita(
      indice: indice,
      nomeSalvo: nomeSalvo,
      slugSalvo: slugSalvo,
      productIdSalvo: pid,
      quantidadeExigida: qtd,
      status: StatusLinhaReceitaAuditoria.produtoNaoEncontrado,
      observacaoTecnica:
          'Nenhum produto na loja com este nome normalizado (após slug sem match).',
      acaoRecomendada:
          'Verificar ortografia do item ou cadastrar o produto; depois vincular com productId.',
    );
  }

  static StatusComboAuditoria _statusComboAgregado(
    List<AuditoriaLinhaReceita> linhas,
    bool receitaVaziaOuMalformada,
  ) {
    if (receitaVaziaOuMalformada) {
      return StatusComboAuditoria.critico;
    }
    var temInvalido = false;
    var temAmbiguoOuNaoEncontrado = false;
    var temRessalva = false;
    var temInconsistente = false;
    var todosCanon = true;

    for (final l in linhas) {
      switch (l.status) {
        case StatusLinhaReceitaAuditoria.okCanonico:
          break;
        case StatusLinhaReceitaAuditoria.semProductIdMasResolvivel:
          todosCanon = false;
          temRessalva = true;
          break;
        case StatusLinhaReceitaAuditoria.ambiguo:
        case StatusLinhaReceitaAuditoria.produtoNaoEncontrado:
          todosCanon = false;
          temAmbiguoOuNaoEncontrado = true;
          break;
        case StatusLinhaReceitaAuditoria.productIdInvalido:
          todosCanon = false;
          temInvalido = true;
          break;
        case StatusLinhaReceitaAuditoria.receitaLinhaInconsistente:
          todosCanon = false;
          temInconsistente = true;
          break;
      }
    }

    if (temInvalido || temInconsistente) return StatusComboAuditoria.critico;
    if (temAmbiguoOuNaoEncontrado) return StatusComboAuditoria.pendente;
    if (temRessalva) return StatusComboAuditoria.okComRessalvas;
    if (todosCanon && linhas.isNotEmpty) return StatusComboAuditoria.ok;
    return StatusComboAuditoria.critico;
  }

  static List<String> _coletarAcoesLinhas(List<AuditoriaLinhaReceita> linhas) {
    final out = <String>[];
    for (final l in linhas) {
      if (l.acaoRecomendada != 'Nenhuma — componente canônico.') {
        out.add('Linha ${l.indice}: ${l.acaoRecomendada}');
      }
    }
    return out;
  }

  /// Auditoria completa para uma loja. **Não grava Hive/Firestore.**
  static RelatorioAuditoriaCombos auditarLoja({
    required String lojaId,
    required Iterable<Produto> todosProdutos,
  }) {
    final combos = _combosDaLoja(lojaId, todosProdutos);
    final naoCombo = _produtosNaoComboLoja(lojaId, todosProdutos);

    final resultados = <AuditoriaComboResultado>[];
    final contagemLinha = <String, int>{};
    for (final s in StatusLinhaReceitaAuditoria.values) {
      contagemLinha[_strLinha(s)] = 0;
    }

    var totalLinhas = 0;
    var combosOk = 0;
    var combosPend = 0;

    for (final combo in combos) {
      final rawList = combo.itensCombo;
      final receitaVazia = rawList == null || rawList.isEmpty;

      final linhas = <AuditoriaLinhaReceita>[];

      if (!receitaVazia) {
        final lista = rawList;
        for (var i = 0; i < lista.length; i++) {
          final row = lista[i];
          final m = Map<String, dynamic>.from(
            row.map((k, v) => MapEntry(k.toString(), v)),
          );
          final linha = auditarLinha(
            indice: i,
            raw: m,
            produtosNaoCombo: naoCombo,
          );
          linhas.add(linha);
          contagemLinha[_strLinha(linha.status)] =
              (contagemLinha[_strLinha(linha.status)] ?? 0) + 1;
          totalLinhas++;
        }
      }

      final statusGeral = _statusComboAgregado(
        linhas,
        receitaVazia,
      );

      if (statusGeral == StatusComboAuditoria.ok) combosOk++;
      if (statusGeral != StatusComboAuditoria.ok) combosPend++;

      String obsCombo;
      if (receitaVazia) {
        obsCombo =
            'Receita vazia (null ou lista vazia) — combo sem componentes mínimos.';
      } else {
        obsCombo = switch (statusGeral) {
          StatusComboAuditoria.ok =>
            'Todos os componentes com productId válido e produto existente.',
          StatusComboAuditoria.okComRessalvas =>
            'Há legado resolvível (único candidato) sem productId gravado — OK com ressalvas.',
          StatusComboAuditoria.pendente =>
            'Há ambiguidade ou produto não encontrado em ao menos uma linha.',
          StatusComboAuditoria.critico =>
            'productId inválido, linha inconsistente ou receita inaceitável.',
        };
      }

      final slugC = combo.slug;
      final pidC = combo.idFirebase;

      final acoes = <String>[];
      if (receitaVazia) {
        acoes.add(
          'Incluir componentes válidos no cadastro do combo ou revisar tipo do produto.',
        );
      } else {
        acoes.addAll(_coletarAcoesLinhas(linhas));
      }

      resultados.add(
        AuditoriaComboResultado(
          nomeCombo: combo.nome,
          productIdCombo: pidC,
          slugCombo: slugC,
          quantidadeItensReceita: linhas.length,
          statusGeral: statusGeral,
          linhas: linhas,
          observacaoCombo: obsCombo,
          acoesRecomendadasCombo: acoes.isEmpty ? ['Nenhuma ação crítica.'] : acoes,
        ),
      );
    }

    final resumo = ResumoExecutivoAuditoriaCombos(
      lojaId: lojaId,
      totalCombosAnalisados: combos.length,
      totalCombos100PorcentoOk: combosOk,
      totalCombosComPendencia: combosPend,
      totalComponentesAuditados: totalLinhas,
      contagemPorStatusLinha: contagemLinha,
    );

    return RelatorioAuditoriaCombos(resumo: resumo, combos: resultados);
  }

  /// Convenience: imprime relatório (ex.: chamada manual em debug). **Não persiste.**
  static String gerarTexto({
    required String lojaId,
    required Iterable<Produto> todosProdutos,
  }) {
    return auditarLoja(lojaId: lojaId, todosProdutos: todosProdutos)
        .comoTextoFormatado();
  }
}
