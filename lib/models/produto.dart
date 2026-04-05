// lib/models/produto.dart
import 'package:hive/hive.dart';

import '../core/produto_variacao_extra.dart';

part 'produto.g.dart';

@HiveType(typeId: 2)
class Produto extends HiveObject {
  @HiveField(0)
  String nome;

  @HiveField(1)
  double custoReal;

  @HiveField(2)
  double frete;

  @HiveField(3)
  double gastosFixos;

  @HiveField(4)
  double gastosVariaveis;

  @HiveField(5)
  double precoSugerido;

  @HiveField(6)
  double precoFinal;

  @HiveField(7)
  int quantidade;

  @HiveField(8)
  double precoUnitario;

  @HiveField(9)
  String categoria;

  @HiveField(10)
  DateTime dataEntrada;

  @HiveField(11)
  String descricao;

  @HiveField(12)
  List<String> imagens;

  @HiveField(13)
  bool publicadoNoCatalogo;

  @HiveField(14)
  String slug;

  @HiveField(15)
  List<String> tamanhos;

  @HiveField(16)
  String subcategoria;

  @HiveField(17)
  Map<String, int> estoquePorTamanho;

  @HiveField(28)
  List<String> cores;

  @HiveField(18)
  bool ativoNoRascunho;

  @HiveField(19)
  String idFirebase;

  @HiveField(20)
  String lojaId;

  // ==============================
  // CAMPOS DE PROMOÇÃO
  // ==============================
  @HiveField(21, defaultValue: false)
  bool emPromocao;

  @HiveField(22)
  double? percentualPromo;

  @HiveField(23)
  double? valorPromo;

  @HiveField(24)
  DateTime? dataInicioPromo;

  @HiveField(25)
  DateTime? dataFimPromo;

  // ==============================
  // PESO PARA CÁLCULO DE FRETE
  // ==============================
  @HiveField(26, defaultValue: 0.0)
  double peso; // peso em gramas

  @HiveField(27, defaultValue: 'padrao')
  String tipoEmbalagem; // tipo da embalagem: pequena, media, grande, etc

  // ==============================
  // MARKETPLACES SELECIONADOS
  // ==============================
  @HiveField(29, defaultValue: <String>[])
  List<String> marketplaces; // Lista de marketplaces: 'mercadolivre', 'shopee', 'magazineluiza', 'amazon'

  // ==============================
  // VARIAÇÕES (TAMANHO + COR)
  // ==============================
  @HiveField(30)
  Map<String, dynamic>? variacoes; // {tamanho: {cor: qtd | {extraValor: qtd}}}

  /// Rótulos do eixo extra: {tamanho: {cor: {extraValor: extraTipo}}}.
  @HiveField(43)
  Map<String, dynamic>? variacoesExtraTipo;

  // ==============================
  // PARCELAMENTO
  // ==============================
  @HiveField(31, defaultValue: false)
  bool divideSemJuros; // true = exibe "12x sem juros"; false = usa juros do gateway

  @HiveField(32, defaultValue: 0.0)
  double percentualDescontoPix; // ex: 5 = 5% desconto no PIX (R$100 cartão → R$95 PIX)

  @HiveField(33, defaultValue: 12)
  int maxParcelasSemJuros; // ex: 3 = até 3x sem juros (quando divideSemJuros = true)

  @HiveField(34, defaultValue: '')
  String videoUrl; // URL do vídeo do produto (opcional, exibido no catálogo)

  /// Código de barras (opcional). Permite buscar e dar baixa pelo código.
  @HiveField(35, defaultValue: '')
  String codigoBarras;

  /// Estoque mínimo (alerta). Se > 0, produto é "estoque baixo" quando quantidade <= estoqueMinimo. Se 0, usa padrão 5.
  @HiveField(36, defaultValue: 0)
  int estoqueMinimo;

  /// Preço por tamanho. Quando preenchido, cada tamanho tem seu próprio preço (ex: P=50, M=75, G=100).
  /// No catálogo exibe "R$ 50,00 até R$ 100,00".
  @HiveField(37)
  Map<String, double>? precoPorTamanho;

  /// Tipo: 'simples' (padrão) ou 'combo'. Combo = produto virtual que agrupa outros; ao vender dá baixa em cada item.
  @HiveField(38, defaultValue: 'simples')
  String tipoProduto;

  /// Itens do combo. Cada mapa: {nome, slug, quantidade, tamanho?, cor?, productId?}.
  /// productId = idFirebase do componente; cadastro novo exige preenchimento (normalização preenche legado quando seguro).
  /// Só usado quando tipoProduto == 'combo'.
  @HiveField(39)
  List<Map<String, dynamic>>? itensCombo;

  /// Data da última alteração (salvo/sincronizado). Usado para filtro "recentemente alterados".
  @HiveField(40)
  DateTime? updatedAt;

  /// true = última edição veio do cadastro (produto/combo/catálogo/import): no pull Firestore→Hive
  /// **não** aplicar snapshot remoto (todos os campos). false = aceitar nuvem (ex.: Precificação).
  @HiveField(41, defaultValue: false)
  bool custoEditadoNoCadastro;

  /// Nome ou identificação do fornecedor (opcional).
  @HiveField(42, defaultValue: '')
  String fornecedor;

  Produto({
    required this.nome,
    required this.custoReal,
    required this.frete,
    required this.gastosFixos,
    required this.gastosVariaveis,
    required this.precoSugerido,
    required this.precoFinal,
    required this.quantidade,
    required this.precoUnitario,
    required this.categoria,
    required this.dataEntrada,
    this.descricao = '',
    this.imagens = const [],
    this.publicadoNoCatalogo = false,
    this.slug = '',
    this.tamanhos = const [],
    this.subcategoria = '',
    this.estoquePorTamanho = const {},
    this.cores = const [],
    this.ativoNoRascunho = true,
    this.idFirebase = '',
    this.lojaId = '',
    this.emPromocao = false,
    this.percentualPromo,
    this.valorPromo,
    this.dataInicioPromo,
    this.dataFimPromo,
    this.peso = 0.0,
    this.tipoEmbalagem = 'padrao',
    this.marketplaces = const [],
    this.variacoes,
    this.variacoesExtraTipo,
    this.divideSemJuros = false,
    this.percentualDescontoPix = 0.0,
    this.maxParcelasSemJuros = 12,
    this.videoUrl = '',
    this.codigoBarras = '',
    this.estoqueMinimo = 0,
    this.precoPorTamanho,
    this.tipoProduto = 'simples',
    this.itensCombo,
    this.updatedAt,
    this.custoEditadoNoCadastro = false,
    this.fornecedor = '',
  });

  bool get ehCombo => tipoProduto == 'combo';

  /// Calcula o preço com promoção aplicada
  double get precoComPromocao {
    if (!emPromocao) return precoFinal;

    // Verifica se a promoção está dentro do período válido
    final now = DateTime.now();
    if (dataInicioPromo != null && now.isBefore(dataInicioPromo!)) {
      return precoFinal;
    }
    if (dataFimPromo != null && now.isAfter(dataFimPromo!)) {
      return precoFinal;
    }

    // Aplica desconto percentual
    if (percentualPromo != null && percentualPromo! > 0) {
      final desconto = precoFinal * (percentualPromo! / 100);
      return (precoFinal - desconto).clamp(0.0, double.infinity);
    }

    // Aplica desconto em valor fixo
    if (valorPromo != null && valorPromo! > 0) {
      return (precoFinal - valorPromo!).clamp(0.0, double.infinity);
    }

    return precoFinal;
  }

  /// Verifica se a promoção está ativa no momento
  bool get promocaoAtiva {
    if (!emPromocao) return false;

    final now = DateTime.now();
    if (dataInicioPromo != null && now.isBefore(dataInicioPromo!)) {
      return false;
    }
    if (dataFimPromo != null && now.isAfter(dataFimPromo!)) {
      return false;
    }

    return (percentualPromo != null && percentualPromo! > 0) ||
        (valorPromo != null && valorPromo! > 0);
  }

  /// helper para "produto vazio" usado em buscas
  factory Produto.vazio() {
    return Produto(
      nome: '',
      custoReal: 0,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 0,
      quantidade: 0,
      precoUnitario: 0,
      categoria: '',
      dataEntrada: DateTime.fromMillisecondsSinceEpoch(0),
      descricao: '',
      imagens: const [],
      publicadoNoCatalogo: false,
      slug: '',
      tamanhos: const [],
      subcategoria: '',
      estoquePorTamanho: const {},
      ativoNoRascunho: false,
      idFirebase: '',
      lojaId: '',
      emPromocao: false,
      marketplaces: const [],
      divideSemJuros: false,
      percentualDescontoPix: 0.0,
      maxParcelasSemJuros: 12,
      videoUrl: '',
      codigoBarras: '',
      estoqueMinimo: 0,
      precoPorTamanho: null,
      tipoProduto: 'simples',
      itensCombo: null,
      custoEditadoNoCadastro: false,
      fornecedor: '',
    );
  }

  /// Retorna o preço para uma variação (tamanho ou tamanho+cor). Usa precoPorTamanho se houver, senão precoFinal.
  double precoParaVariacao(String tamanho, [String? cor]) {
    if (precoPorTamanho != null && precoPorTamanho!.containsKey(tamanho)) {
      return precoPorTamanho![tamanho] ?? precoFinal;
    }
    return precoFinal;
  }

  /// Retorna (menor, maior) preço considerando precoPorTamanho. Se não houver, retorna (precoFinal, precoFinal).
  (double, double) get faixaPrecoVariacoes {
    if (precoPorTamanho == null || precoPorTamanho!.isEmpty) {
      return (precoFinal, precoFinal);
    }
    final precos = precoPorTamanho!.values.where((v) => v > 0).toList();
    if (precos.isEmpty) return (precoFinal, precoFinal);
    return (precos.reduce((a, b) => a < b ? a : b), precos.reduce((a, b) => a > b ? a : b));
  }

  /// Considera estoque baixo: se estoqueMinimo > 0 usa ele, senão usa padrão 5. Não altera dados existentes.
  bool get isEstoqueBaixo {
    final minimo = estoqueMinimo > 0 ? estoqueMinimo : 5;
    return quantidade >= 0 && quantidade <= minimo;
  }

  /// compatibilidade com quem usa Produto.empty()
  static Produto empty() => Produto.vazio();
    // ==============================
  // ESTOQUE POR TAMANHO (GRADE)
  // ==============================

  /// Recalcula a quantidade total com base no mapa estoquePorTamanho
  void _recalcularQuantidadeAPartirDoMapa() {
    if (estoquePorTamanho.isEmpty) {
      // se não tiver grade, mantém o valor atual
      return;
    }

    int total = 0;
    for (final v in estoquePorTamanho.values) {
      total += v;
    }
    quantidade = total;
  }

  /// Debita do estoque apenas do tamanho informado
  /// Ex.: debitarEstoquePorTamanho("18", 2)
  void debitarEstoquePorTamanho(String tamanho, int qtd) {
    if (qtd <= 0) return;

    final mapa = Map<String, int>.from(estoquePorTamanho);

    final atual = mapa[tamanho] ?? 0;
    if (atual < qtd) {
      throw Exception(
        'Estoque insuficiente para o tamanho $tamanho. Em estoque: $atual, venda: $qtd',
      );
    }

    mapa[tamanho] = atual - qtd;
    if (mapa[tamanho]! <= 0) {
      mapa.remove(tamanho);
    }

    estoquePorTamanho = mapa;
    _recalcularQuantidadeAPartirDoMapa();
  }

  /// Devolve estoque para um tamanho (usado ao desfazer venda)
  void devolverEstoquePorTamanho(String tamanho, int qtd) {
    if (qtd <= 0) return;

    final mapa = Map<String, int>.from(estoquePorTamanho);
    mapa[tamanho] = (mapa[tamanho] ?? 0) + qtd;

    estoquePorTamanho = mapa;
    _recalcularQuantidadeAPartirDoMapa();
  }

  // ==============================
  // VARIAÇÕES (TAMANHO + COR)
  // ==============================

  /// Verifica se o produto usa sistema de variações
  bool get usaVariacoes => variacoes != null && variacoes!.isNotEmpty;

  /// Produto tem variação APENAS de tamanho (sem cor)
  bool get temVariacaoSoloTamanho {
    if (!usaVariacoes) return estoquePorTamanho.isNotEmpty;
    final keys = variacoes!.keys.where((k) => k != 'sem-tamanho').toList();
    if (keys.isEmpty) return false;
    for (final t in keys) {
      final m = variacoes![t];
      if (m is Map && m.isNotEmpty) return true;
    }
    return false;
  }

  /// Produto tem variação APENAS de cor (sem tamanho)
  bool get temVariacaoSoloCor {
    if (!usaVariacoes) return false;
    final semTamanho = variacoes!['sem-tamanho'];
    return semTamanho is Map && semTamanho.isNotEmpty;
  }

  /// Produto tem variação de tamanho E cor (exige selecionar ambos)
  bool get temVariacaoTamanhoECor {
    if (!usaVariacoes) return false;
    for (final entry in variacoes!.entries) {
      if (entry.key == 'sem-tamanho') continue;
      final mapa = entry.value;
      if (mapa is! Map) continue;
      for (final k in mapa.keys) {
        if (k != null && k.toString() != 'sem-cor') return true;
      }
    }
    return false;
  }

  /// Obtém estoque por cor (quando produto tem só variação de cor)
  Map<String, int> get estoquePorCor {
    if (!usaVariacoes) return {};
    final semTamanho = variacoes!['sem-tamanho'];
    if (semTamanho == null || semTamanho is! Map) return {};
    return semTamanho.map(
      (k, v) => MapEntry(k.toString(), ProdutoVariacaoExtra.somarCelula(v)),
    );
  }

  /// Obtém o estoque de uma variação específica (tamanho + cor)
  /// Para só cor: tamanho vazio, cor preenchida -> variacoes['sem-tamanho'][cor]
  /// Para só tamanho: tamanho preenchido, cor vazia/sem-cor -> variacoes[tamanho]['sem-cor']
  /// Para ambos: variacoes[tamanho][cor]
  /// [variacaoExtra]: quando a célula é mapa de extras, filtra pela chave; vazio = legado ou chave ''.
  int obterEstoqueVariacao(String tamanho, String cor, [String variacaoExtra = '']) {
    if (!usaVariacoes) return 0;

    final tam = tamanho.trim();
    final corTrim = cor.trim();
    final ex = variacaoExtra.trim();

    if (tam.isEmpty && corTrim.isNotEmpty) {
      final mapaCor = variacoes!['sem-tamanho'];
      if (mapaCor == null || mapaCor is! Map) return 0;
      final cell = mapaCor[corTrim];
      return ProdutoVariacaoExtra.quantidadeNaCelula(cell, ex);
    }

    if (tam.isNotEmpty) {
      final mapaTamanho = variacoes![tam];
      if (mapaTamanho == null || mapaTamanho is! Map) return 0;
      final corKey = corTrim.isEmpty ? 'sem-cor' : corTrim;
      final cell = mapaTamanho[corKey];
      return ProdutoVariacaoExtra.quantidadeNaCelula(cell, ex);
    }

    return 0;
  }

  /// Obtém todas as cores disponíveis para um tamanho específico
  /// Se tamanho vazio e temVariacaoSoloCor: retorna cores de variacoes['sem-tamanho']
  List<String> obterCoresPorTamanho(String tamanho) {
    if (!usaVariacoes) return cores;

    final tam = tamanho.trim();
    if (tam.isEmpty && temVariacaoSoloCor) {
      final semTam = variacoes!['sem-tamanho'];
      if (semTam is! Map) return [];
      return semTam.keys
          .where((c) => ProdutoVariacaoExtra.somarCelula(semTam[c]) > 0)
          .cast<String>()
          .toList();
    }

    final mapaTamanho = variacoes![tam];
    if (mapaTamanho == null || mapaTamanho is! Map) return [];

    return mapaTamanho.keys
        .where((c) => ProdutoVariacaoExtra.somarCelula(mapaTamanho[c]) > 0)
        .cast<String>()
        .toList();
  }

  /// Debita estoque de uma variação específica
  void debitarEstoqueVariacao(String tamanho, String cor, int qtd,
      [String variacaoExtra = '']) {
    if (qtd <= 0) return;
    if (!usaVariacoes) return;

    final tam = tamanho.trim();
    final corKey = cor.trim().isEmpty ? 'sem-cor' : cor.trim();
    final chaveTamanho = tam.isEmpty ? 'sem-tamanho' : tam;
    final ex = variacaoExtra.trim();

    final mapa = Map<String, dynamic>.from(variacoes!);
    final mapaInterno = Map<String, dynamic>.from(mapa[chaveTamanho] ?? {});

    final cell = mapaInterno[corKey];
    final r = ProdutoVariacaoExtra.debitarCelula(cell, ex, qtd);
    if (!r.ok) {
      final disp = ProdutoVariacaoExtra.quantidadeNaCelula(cell, ex);
      throw Exception(
        'Estoque insuficiente para ${tam.isEmpty ? "cor" : tam}${cor.isEmpty ? "" : " - $cor"}. Em estoque: $disp, venda: $qtd',
      );
    }
    if (r.newCell == ProdutoVariacaoExtra.removeCorCell) {
      mapaInterno.remove(corKey);
    } else {
      mapaInterno[corKey] = r.newCell;
    }

    mapa[chaveTamanho] = mapaInterno;
    if (mapaInterno.isEmpty) {
      mapa.remove(chaveTamanho);
    }

    variacoes = mapa;
    _recalcularQuantidadeTotalVariacoes();
  }

  /// Devolve estoque de uma variação
  void devolverEstoqueVariacao(String tamanho, String cor, int qtd,
      [String variacaoExtra = '']) {
    if (qtd <= 0) return;
    if (!usaVariacoes) return;

    final tam = tamanho.trim();
    final corKey = cor.trim().isEmpty ? 'sem-cor' : cor.trim();
    final chaveTamanho = tam.isEmpty ? 'sem-tamanho' : tam;
    final ex = variacaoExtra.trim();

    final mapa = Map<String, dynamic>.from(variacoes!);
    final mapaInterno = Map<String, dynamic>.from(mapa[chaveTamanho] ?? {});

    final cell = mapaInterno[corKey];
    mapaInterno[corKey] = ProdutoVariacaoExtra.devolverCelula(cell, ex, qtd);

    mapa[chaveTamanho] = mapaInterno;
    variacoes = mapa;
    _recalcularQuantidadeTotalVariacoes();
  }

  /// Recalcula a quantidade total com base nas variações
  void _recalcularQuantidadeTotalVariacoes() {
    if (!usaVariacoes) return;

    int total = 0;
    for (final mapaTamanho in variacoes!.values) {
      if (mapaTamanho is! Map) continue;
      for (final qtd in mapaTamanho.values) {
        total += ProdutoVariacaoExtra.somarCelula(qtd);
      }
    }
    quantidade = total;
  }

  /// Método público para recalcular quantidade total (útil após adicionar/editar variações manualmente).
  /// Considera variações (tamanho+cor) ou estoquePorTamanho quando variações está vazio.
  void recalcularQuantidadeTotal() {
    if (usaVariacoes) {
      _recalcularQuantidadeTotalVariacoes();
    } else if (estoquePorTamanho.isNotEmpty) {
      _recalcularQuantidadeAPartirDoMapa();
    }
  }

}