import 'package:hive/hive.dart';

part 'produto_catalogo.g.dart';

@HiveType(typeId: 5)
class ProdutoCatalogo extends HiveObject {
  @HiveField(0)
  String nome;

  @HiveField(1)
  String? descricao;

  @HiveField(2)
  String? sobre;

  @HiveField(3)
  List<String> tamanhos;

  @HiveField(4)
  int quantidade;

  @HiveField(5)
  double precoFinal;

  @HiveField(6)
  double precoUnitario;

  @HiveField(7)
  double precoSugerido;

  @HiveField(8)
  double custoReal;

  @HiveField(9)
  double frete;

  @HiveField(10)
  double gastosFixos;

  @HiveField(11)
  double gastosVariaveis;

  @HiveField(12)
  String categoria;

  @HiveField(13)
  String? subcategoria;

  @HiveField(14)
  DateTime dataEntrada;

  @HiveField(15)
  List<String> imagens;

  @HiveField(16) // 🔥 novo campo
  String lojaId;

  @HiveField(17)
  List<String> cores;

  @HiveField(18)
  Map<String, dynamic>? variacoes; // Estrutura: {tamanho: {cor: quantidade}}

  ProdutoCatalogo({
    required this.nome,
    this.descricao,
    this.sobre,
    this.tamanhos = const [],
    required this.quantidade,
    required this.precoFinal,
    required this.precoUnitario,
    required this.precoSugerido,
    required this.custoReal,
    required this.frete,
    required this.gastosFixos,
    required this.gastosVariaveis,
    required this.categoria,
    this.subcategoria = '',
    required this.dataEntrada,
    this.imagens = const [],
    required this.lojaId, // 🔥 obrigatório na criação
    this.cores = const [],
    this.variacoes,
  });

  /// Verifica se o produto usa sistema de variações
  bool get usaVariacoes => variacoes != null && variacoes!.isNotEmpty;

  /// Obtém o estoque de uma variação específica (tamanho + cor)
  int obterEstoqueVariacao(String tamanho, String cor) {
    if (!usaVariacoes) return 0;

    final mapaTamanho = variacoes![tamanho];
    if (mapaTamanho == null || mapaTamanho is! Map) return 0;

    return (mapaTamanho[cor] as num?)?.toInt() ?? 0;
  }

  /// Obtém todas as cores disponíveis para um tamanho específico
  List<String> obterCoresPorTamanho(String tamanho) {
    if (!usaVariacoes) return cores;

    final mapaTamanho = variacoes![tamanho];
    if (mapaTamanho == null || mapaTamanho is! Map) return [];

    return mapaTamanho.keys
        .where((cor) => ((mapaTamanho[cor] as num?)?.toInt() ?? 0) > 0)
        .cast<String>()
        .toList();
  }
}