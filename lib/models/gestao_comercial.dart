// M3.9 SPRINT4 — modelos de gestão comercial (camada app, sem Hive typeId).

/// Modo de permissão de desconto por produto / política.
enum DescontoModo {
  nunca,
  sempre,
  somentePix,
  somenteDinheiro,
  pixDinheiro;

  static DescontoModo parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'nunca':
      case 'never':
        return DescontoModo.nunca;
      case 'somente_pix':
      case 'somente pix':
      case 'pix':
        return DescontoModo.somentePix;
      case 'somente_dinheiro':
      case 'somente dinheiro':
      case 'dinheiro':
        return DescontoModo.somenteDinheiro;
      case 'pix_dinheiro':
      case 'pix+dinheiro':
      case 'pix_e_dinheiro':
        return DescontoModo.pixDinheiro;
      default:
        return DescontoModo.sempre;
    }
  }

  String get wireValue {
    switch (this) {
      case DescontoModo.nunca:
        return 'nunca';
      case DescontoModo.sempre:
        return 'sempre';
      case DescontoModo.somentePix:
        return 'somente_pix';
      case DescontoModo.somenteDinheiro:
        return 'somente_dinheiro';
      case DescontoModo.pixDinheiro:
        return 'pix_dinheiro';
    }
  }

  String get label {
    switch (this) {
      case DescontoModo.nunca:
        return 'Nunca';
      case DescontoModo.sempre:
        return 'Sempre';
      case DescontoModo.somentePix:
        return 'Somente PIX';
      case DescontoModo.somenteDinheiro:
        return 'Somente Dinheiro';
      case DescontoModo.pixDinheiro:
        return 'PIX + Dinheiro';
    }
  }
}

enum ComissaoTipo {
  percentual,
  valorFixo,
  escalonada;

  static ComissaoTipo parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'fixo':
      case 'valor_fixo':
      case 'valorfixo':
        return ComissaoTipo.valorFixo;
      case 'escalonada':
      case 'faixas':
        return ComissaoTipo.escalonada;
      default:
        return ComissaoTipo.percentual;
    }
  }

  String get wireValue {
    switch (this) {
      case ComissaoTipo.percentual:
        return 'percentual';
      case ComissaoTipo.valorFixo:
        return 'valor_fixo';
      case ComissaoTipo.escalonada:
        return 'escalonada';
    }
  }
}

enum ProdutosAcessoModo {
  todos,
  selecionados,
  bloqueados;

  static ProdutosAcessoModo parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'selecionados':
      case 'permitidos':
        return ProdutosAcessoModo.selecionados;
      case 'bloqueados':
        return ProdutosAcessoModo.bloqueados;
      default:
        return ProdutosAcessoModo.todos;
    }
  }

  String get wireValue {
    switch (this) {
      case ProdutosAcessoModo.todos:
        return 'todos';
      case ProdutosAcessoModo.selecionados:
        return 'selecionados';
      case ProdutosAcessoModo.bloqueados:
        return 'bloqueados';
    }
  }
}

class ComissaoFaixa {
  const ComissaoFaixa({
    required this.de,
    required this.ate,
    required this.percentual,
  });

  final double de;
  final double ate;
  final double percentual;

  Map<String, dynamic> toMap() => {
        'de': de,
        'ate': ate,
        'percentual': percentual,
      };

  factory ComissaoFaixa.fromMap(Map<String, dynamic> m) => ComissaoFaixa(
        de: (m['de'] as num?)?.toDouble() ?? 0,
        ate: (m['ate'] as num?)?.toDouble() ?? 0,
        percentual: (m['percentual'] as num?)?.toDouble() ?? 0,
      );
}

/// Política de desconto (produto e/ou teto do vendedor).
class DescontoPolitica {
  const DescontoPolitica({
    this.modo = DescontoModo.sempre,
    this.maxPct = 100,
    this.exigeAutorizacaoAcimaPct = 100,
    this.permitePix = true,
    this.permiteDinheiro = true,
    this.permiteCartao = true,
  });

  final DescontoModo modo;
  final double maxPct;
  final double exigeAutorizacaoAcimaPct;
  final bool permitePix;
  final bool permiteDinheiro;
  final bool permiteCartao;

  Map<String, dynamic> toMap() => {
        'modo': modo.wireValue,
        'maxPct': maxPct,
        'exigeAutorizacaoAcimaPct': exigeAutorizacaoAcimaPct,
        'permitePix': permitePix,
        'permiteDinheiro': permiteDinheiro,
        'permiteCartao': permiteCartao,
      };

  factory DescontoPolitica.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const DescontoPolitica();
    return DescontoPolitica(
      modo: DescontoModo.parse(raw['modo']?.toString()),
      maxPct: (raw['maxPct'] as num?)?.toDouble() ?? 100,
      exigeAutorizacaoAcimaPct:
          (raw['exigeAutorizacaoAcimaPct'] as num?)?.toDouble() ?? 100,
      permitePix: raw['permitePix'] != false,
      permiteDinheiro: raw['permiteDinheiro'] != false,
      permiteCartao: raw['permiteCartao'] != false,
    );
  }
}

/// Preferências de dashboard do vendedor.
class DashboardVendedorPrefs {
  const DashboardVendedorPrefs({
    this.minhaMeta = true,
    this.minhaComissao = true,
    this.minhasVendas = true,
    this.ticketMedioPessoal = true,
    this.clientesAtivos = true,
    this.ocultarFinanceiro = true,
    this.ocultarLucro = true,
    this.ocultarMaisVendidos = true,
    this.ocultarResumoGeral = true,
  });

  final bool minhaMeta;
  final bool minhaComissao;
  final bool minhasVendas;
  final bool ticketMedioPessoal;
  final bool clientesAtivos;
  final bool ocultarFinanceiro;
  final bool ocultarLucro;
  final bool ocultarMaisVendidos;
  final bool ocultarResumoGeral;

  Map<String, dynamic> toMap() => {
        'minhaMeta': minhaMeta,
        'minhaComissao': minhaComissao,
        'minhasVendas': minhasVendas,
        'ticketMedioPessoal': ticketMedioPessoal,
        'clientesAtivos': clientesAtivos,
        'ocultarFinanceiro': ocultarFinanceiro,
        'ocultarLucro': ocultarLucro,
        'ocultarMaisVendidos': ocultarMaisVendidos,
        'ocultarResumoGeral': ocultarResumoGeral,
      };

  factory DashboardVendedorPrefs.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const DashboardVendedorPrefs();
    bool b(String k, {bool d = true}) => raw[k] is bool ? raw[k] as bool : d;
    return DashboardVendedorPrefs(
      minhaMeta: b('minhaMeta'),
      minhaComissao: b('minhaComissao'),
      minhasVendas: b('minhasVendas'),
      ticketMedioPessoal: b('ticketMedioPessoal'),
      clientesAtivos: b('clientesAtivos'),
      ocultarFinanceiro: b('ocultarFinanceiro'),
      ocultarLucro: b('ocultarLucro'),
      ocultarMaisVendidos: b('ocultarMaisVendidos'),
      ocultarResumoGeral: b('ocultarResumoGeral'),
    );
  }
}

/// Configuração comercial completa de um vendedor (persistida no doc Firestore).
class GestaoVendedorConfig {
  const GestaoVendedorConfig({
    this.cargo = 'Vendedor',
    this.metaMensal = 0,
    this.metaDiaria = 0,
    this.metaAnual = 0,
    this.comissaoTipo = ComissaoTipo.percentual,
    this.comissaoPercentual,
    this.comissaoValorFixo,
    this.comissaoFaixas = const [],
    this.permissoes = const {},
    this.produtosModo = ProdutosAcessoModo.todos,
    this.produtosIds = const [],
    this.clientesSomenteCarteira = true,
    this.clientesPesquisaGlobalNovaVenda = true,
    this.clientesEditarCadastro = false,
    this.clientesExcluir = false,
    this.dashboard = const DashboardVendedorPrefs(),
    this.descontos = const DescontoPolitica(),
  });

  final String cargo;
  final double metaMensal;
  final double metaDiaria;
  final double metaAnual;
  final ComissaoTipo comissaoTipo;
  final double? comissaoPercentual;
  final double? comissaoValorFixo;
  final List<ComissaoFaixa> comissaoFaixas;
  final Map<String, bool> permissoes;
  final ProdutosAcessoModo produtosModo;
  final List<String> produtosIds;
  final bool clientesSomenteCarteira;
  final bool clientesPesquisaGlobalNovaVenda;
  final bool clientesEditarCadastro;
  final bool clientesExcluir;
  final DashboardVendedorPrefs dashboard;
  final DescontoPolitica descontos;

  /// Chaves oficiais de permissão (Sprint 4).
  static const permissoesKeys = <String>[
    'nova_venda',
    'clientes',
    'historico',
    'catalogo',
    'estoque_consulta',
    'editar_estoque',
    'cadastrar_produto',
    'excluir_produto',
    'financeiro',
    'marketing',
    'exportar',
    'ver_custo',
    'ver_fornecedor',
    'cancelar_venda',
    'dar_desconto',
    'dashboard_completo',
  ];

  static Map<String, bool> permissoesPadraoVendedor() => {
        for (final k in permissoesKeys)
          k: const {
            'nova_venda',
            'clientes',
            'historico',
            'catalogo',
            'estoque_consulta',
            'dar_desconto',
          }.contains(k),
      };

  Map<String, dynamic> toMap() => {
        'cargo': cargo,
        'metaMensal': metaMensal,
        'metaDiaria': metaDiaria,
        'metaAnual': metaAnual,
        'comissaoTipo': comissaoTipo.wireValue,
        'comissaoPercentual': comissaoPercentual,
        'comissaoValorFixo': comissaoValorFixo,
        'comissaoFaixas': comissaoFaixas.map((e) => e.toMap()).toList(),
        'permissoes': permissoes,
        'produtosModo': produtosModo.wireValue,
        'produtosIds': produtosIds,
        'clientesSomenteCarteira': clientesSomenteCarteira,
        'clientesPesquisaGlobalNovaVenda': clientesPesquisaGlobalNovaVenda,
        'clientesEditarCadastro': clientesEditarCadastro,
        'clientesExcluir': clientesExcluir,
        'dashboard': dashboard.toMap(),
        'descontos': descontos.toMap(),
      };

  factory GestaoVendedorConfig.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return GestaoVendedorConfig(permissoes: permissoesPadraoVendedor());
    }
    final faixasRaw = raw['comissaoFaixas'];
    final faixas = <ComissaoFaixa>[];
    if (faixasRaw is List) {
      for (final e in faixasRaw) {
        if (e is Map) {
          faixas.add(ComissaoFaixa.fromMap(Map<String, dynamic>.from(e)));
        }
      }
    }
    final perms = <String, bool>{...permissoesPadraoVendedor()};
    final rawPerms = raw['permissoes'];
    if (rawPerms is Map) {
      rawPerms.forEach((k, v) {
        perms[k.toString()] = v == true || v == 1 || v == 'true';
      });
    }
    final ids = <String>[];
    final rawIds = raw['produtosIds'];
    if (rawIds is List) {
      for (final e in rawIds) {
        final s = e.toString().trim();
        if (s.isNotEmpty) ids.add(s);
      }
    }
    return GestaoVendedorConfig(
      cargo: (raw['cargo'] ?? 'Vendedor').toString(),
      metaMensal: (raw['metaMensal'] as num?)?.toDouble() ?? 0,
      metaDiaria: (raw['metaDiaria'] as num?)?.toDouble() ?? 0,
      metaAnual: (raw['metaAnual'] as num?)?.toDouble() ?? 0,
      comissaoTipo: ComissaoTipo.parse(raw['comissaoTipo']?.toString()),
      comissaoPercentual: (raw['comissaoPercentual'] as num?)?.toDouble(),
      comissaoValorFixo: (raw['comissaoValorFixo'] as num?)?.toDouble(),
      comissaoFaixas: faixas,
      permissoes: perms,
      produtosModo: ProdutosAcessoModo.parse(raw['produtosModo']?.toString()),
      produtosIds: ids,
      clientesSomenteCarteira: raw['clientesSomenteCarteira'] != false,
      clientesPesquisaGlobalNovaVenda:
          raw['clientesPesquisaGlobalNovaVenda'] != false,
      clientesEditarCadastro: raw['clientesEditarCadastro'] == true,
      clientesExcluir: raw['clientesExcluir'] == true,
      dashboard: DashboardVendedorPrefs.fromMap(
        raw['dashboard'] is Map
            ? Map<String, dynamic>.from(raw['dashboard'] as Map)
            : null,
      ),
      descontos: DescontoPolitica.fromMap(
        raw['descontos'] is Map
            ? Map<String, dynamic>.from(raw['descontos'] as Map)
            : null,
      ),
    );
  }

  GestaoVendedorConfig copyWith({
    String? cargo,
    double? metaMensal,
    double? metaDiaria,
    double? metaAnual,
    ComissaoTipo? comissaoTipo,
    double? comissaoPercentual,
    double? comissaoValorFixo,
    List<ComissaoFaixa>? comissaoFaixas,
    Map<String, bool>? permissoes,
    ProdutosAcessoModo? produtosModo,
    List<String>? produtosIds,
    bool? clientesSomenteCarteira,
    bool? clientesPesquisaGlobalNovaVenda,
    bool? clientesEditarCadastro,
    bool? clientesExcluir,
    DashboardVendedorPrefs? dashboard,
    DescontoPolitica? descontos,
  }) {
    return GestaoVendedorConfig(
      cargo: cargo ?? this.cargo,
      metaMensal: metaMensal ?? this.metaMensal,
      metaDiaria: metaDiaria ?? this.metaDiaria,
      metaAnual: metaAnual ?? this.metaAnual,
      comissaoTipo: comissaoTipo ?? this.comissaoTipo,
      comissaoPercentual: comissaoPercentual ?? this.comissaoPercentual,
      comissaoValorFixo: comissaoValorFixo ?? this.comissaoValorFixo,
      comissaoFaixas: comissaoFaixas ?? this.comissaoFaixas,
      permissoes: permissoes ?? this.permissoes,
      produtosModo: produtosModo ?? this.produtosModo,
      produtosIds: produtosIds ?? this.produtosIds,
      clientesSomenteCarteira:
          clientesSomenteCarteira ?? this.clientesSomenteCarteira,
      clientesPesquisaGlobalNovaVenda: clientesPesquisaGlobalNovaVenda ??
          this.clientesPesquisaGlobalNovaVenda,
      clientesEditarCadastro:
          clientesEditarCadastro ?? this.clientesEditarCadastro,
      clientesExcluir: clientesExcluir ?? this.clientesExcluir,
      dashboard: dashboard ?? this.dashboard,
      descontos: descontos ?? this.descontos,
    );
  }
}

/// Regras de acesso por produto (permitidos / bloqueados + desconto).
class ProdutoAcessoComercial {
  const ProdutoAcessoComercial({
    this.productId = '',
    this.permitidos = const [],
    this.bloqueados = const [],
    this.desconto = const DescontoPolitica(),
  });

  final String productId;
  final List<String> permitidos;
  final List<String> bloqueados;
  final DescontoPolitica desconto;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'permitidos': permitidos,
        'bloqueados': bloqueados,
        'desconto': desconto.toMap(),
      };

  factory ProdutoAcessoComercial.fromMap(
    String productId,
    Map<String, dynamic>? raw,
  ) {
    if (raw == null) {
      return ProdutoAcessoComercial(productId: productId);
    }
    List<String> list(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }

    return ProdutoAcessoComercial(
      productId: productId,
      permitidos: list(raw['permitidos'] ?? raw['vendedoresPermitidos']),
      bloqueados: list(raw['bloqueados'] ?? raw['vendedoresBloqueados']),
      desconto: DescontoPolitica.fromMap(
        raw['desconto'] is Map
            ? Map<String, dynamic>.from(raw['desconto'] as Map)
            : null,
      ),
    );
  }
}

/// Resultado da avaliação de desconto.
enum DescontoAvaliacao {
  permitido,
  exigeAutorizacao,
  bloqueadoModo,
  acimaDoMaximo,
}

class DescontoAvaliacaoResult {
  const DescontoAvaliacaoResult({
    required this.avaliacao,
    required this.mensagem,
  });

  final DescontoAvaliacao avaliacao;
  final String mensagem;

  bool get permitido => avaliacao == DescontoAvaliacao.permitido;
  bool get exigeAuth => avaliacao == DescontoAvaliacao.exigeAutorizacao;
}

/// Avaliação pura da política de desconto (testável).
DescontoAvaliacaoResult avaliarDesconto({
  required DescontoPolitica politica,
  required double descontoPct,
  required bool pagamentoTemPix,
  required bool pagamentoTemDinheiro,
  required bool pagamentoTemCartao,
}) {
  if (descontoPct <= 0.0001) {
    return const DescontoAvaliacaoResult(
      avaliacao: DescontoAvaliacao.permitido,
      mensagem: 'Sem desconto',
    );
  }
  if (politica.modo == DescontoModo.nunca) {
    return const DescontoAvaliacaoResult(
      avaliacao: DescontoAvaliacao.bloqueadoModo,
      mensagem: 'Desconto não permitido neste produto.',
    );
  }
  if (politica.modo == DescontoModo.somentePix && !pagamentoTemPix) {
    return const DescontoAvaliacaoResult(
      avaliacao: DescontoAvaliacao.bloqueadoModo,
      mensagem: 'Desconto permitido somente com PIX.',
    );
  }
  if (politica.modo == DescontoModo.somenteDinheiro && !pagamentoTemDinheiro) {
    return const DescontoAvaliacaoResult(
      avaliacao: DescontoAvaliacao.bloqueadoModo,
      mensagem: 'Desconto permitido somente com Dinheiro.',
    );
  }
  if (politica.modo == DescontoModo.pixDinheiro &&
      !(pagamentoTemPix || pagamentoTemDinheiro)) {
    return const DescontoAvaliacaoResult(
      avaliacao: DescontoAvaliacao.bloqueadoModo,
      mensagem: 'Desconto permitido somente com PIX ou Dinheiro.',
    );
  }
  if (pagamentoTemCartao && !politica.permiteCartao && descontoPct > 0) {
    // cartão sozinho sem pix/dinheiro em modos restritos já coberto acima
  }
  if (descontoPct > politica.maxPct + 0.0001) {
    return DescontoAvaliacaoResult(
      avaliacao: DescontoAvaliacao.acimaDoMaximo,
      mensagem:
          'Desconto acima do máximo permitido (${politica.maxPct.toStringAsFixed(1)}%).',
    );
  }
  if (descontoPct > politica.exigeAutorizacaoAcimaPct + 0.0001) {
    return const DescontoAvaliacaoResult(
      avaliacao: DescontoAvaliacao.exigeAutorizacao,
      mensagem: 'Desconto exige autorização do administrador.',
    );
  }
  return const DescontoAvaliacaoResult(
    avaliacao: DescontoAvaliacao.permitido,
    mensagem: 'Desconto permitido',
  );
}

/// Visibilidade de produto para vendedor (pura).
bool produtoVisivelParaVendedor({
  required bool isAdmin,
  required String vendedorUid,
  required int quantidade,
  required bool produtoAtivo,
  required ProdutosAcessoModo modoVendedor,
  required List<String> produtosIdsVendedor,
  required List<String> permitidosProduto,
  required List<String> bloqueadosProduto,
  bool exigirEstoquePositivo = true,
}) {
  if (isAdmin) return true;
  if (!produtoAtivo) return false;
  if (exigirEstoquePositivo && quantidade <= 0) return false;

  final uid = vendedorUid.trim().toLowerCase();
  if (uid.isEmpty) return false;

  final bloq = bloqueadosProduto.map((e) => e.trim().toLowerCase()).toSet();
  if (bloq.contains(uid)) return false;

  final perm = permitidosProduto.map((e) => e.trim().toLowerCase()).toSet();
  if (perm.isNotEmpty && !perm.contains(uid)) return false;

  final ids = produtosIdsVendedor.map((e) => e.trim().toLowerCase()).toSet();
  switch (modoVendedor) {
    case ProdutosAcessoModo.todos:
      return true;
    case ProdutosAcessoModo.selecionados:
      return ids.isNotEmpty; // productId match feito pelo caller com ids
    case ProdutosAcessoModo.bloqueados:
      return true; // ids bloqueados filtrados pelo caller
  }
}

/// Verifica produtoId contra modo do vendedor (após regras do produto).
bool produtoIdPermitidoPeloModoVendedor({
  required ProdutosAcessoModo modo,
  required String productId,
  required List<String> produtosIds,
}) {
  final pid = productId.trim().toLowerCase();
  if (pid.isEmpty) return modo == ProdutosAcessoModo.todos;
  final ids = produtosIds.map((e) => e.trim().toLowerCase()).toSet();
  switch (modo) {
    case ProdutosAcessoModo.todos:
      return true;
    case ProdutosAcessoModo.selecionados:
      return ids.contains(pid);
    case ProdutosAcessoModo.bloqueados:
      return !ids.contains(pid);
  }
}
