// lib/financeiro/financeiro_constants.dart
// Tipos e categorias do módulo financeiro (strings estáveis para Hive).

/// Tipos de lançamento (valores persistidos — não renomear sem migração).
abstract class FinanceiroTipoLancamento {
  /// Despesa genérica (legado) — continua válida e entra no resultado gerencial.
  static const String despesaOperacional = 'despesa_operacional';
  static const String gastoFixo = 'gasto_fixo';
  static const String gastoVariavel = 'gasto_variavel';
  static const String compraMercadoria = 'compra_mercadoria';
  static const String investimento = 'investimento';
  static const String pagamentoFuncionario = 'pagamento_funcionario';
  static const String proLabore = 'pro_labore';
  static const String entradaExtra = 'entrada_extra';
  static const String ajusteFinanceiro = 'ajuste_financeiro';
  /// Retirada do sócio / distribuição — não é despesa operacional; afeta caixa.
  static const String retirada = 'retirada_financeira';

  static const List<String> todos = [
    gastoFixo,
    gastoVariavel,
    despesaOperacional,
    compraMercadoria,
    investimento,
    pagamentoFuncionario,
    proLabore,
    entradaExtra,
    ajusteFinanceiro,
    retirada,
  ];

  /// Evita crash do dropdown se vier valor legado desconhecido.
  static String tipoOuPadrao(String t) =>
      todos.contains(t) ? t : despesaOperacional;

  static String legivel(String tipo) {
    switch (tipo) {
      case gastoFixo:
        return 'Gasto fixo';
      case gastoVariavel:
        return 'Gasto variável';
      case despesaOperacional:
        return 'Despesa operacional (legado)';
      case compraMercadoria:
        return 'Compra de mercadoria';
      case investimento:
        return 'Investimento';
      case pagamentoFuncionario:
        return 'Salários / funcionários';
      case proLabore:
        return 'Pró-labore';
      case entradaExtra:
        return 'Entrada extra';
      case ajusteFinanceiro:
        return 'Ajuste financeiro';
      case retirada:
        return 'Retirada';
      default:
        return tipo;
    }
  }
}

/// Status do lançamento.
abstract class FinanceiroStatusLancamento {
  static const String pago = 'pago';
  static const String pendente = 'pendente';
}

/// Origem do registro.
abstract class FinanceiroOrigemLancamento {
  static const String manual = 'manual';
  /// Lançamento criado a partir do cadastro de gastos fixos (sugestão do mês).
  static const String geradoGastoFixo = 'gasto_fixo_gerado';
  /// Recebimento registrado a partir da tela Contas a receber (fiado / título).
  static const String contaReceberFiado = 'conta_receber_fiado';
}

/// Grupo para UI (não persiste no tipo).
abstract class FinanceiroGrupoCategoria {
  static const String operacional = 'operacional';
  static const String comercial = 'comercial';
  static const String estoque = 'estoque';
  static const String estrutura = 'estrutura';
  static const String pessoas = 'pessoas';
  static const String educacao = 'educacao';
}

/// Categoria sugerida + subcategorias (expansível no futuro).
class FinanceiroCategoriaPadrao {
  final String grupo;
  final String categoria;
  final List<String> subcategorias;

  const FinanceiroCategoriaPadrao({
    required this.grupo,
    required this.categoria,
    required this.subcategorias,
  });
}

/// Lista padrão para dropdowns (categoria = chave principal).
const List<FinanceiroCategoriaPadrao> kFinanceiroCategoriasPadrao = [
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.operacional,
    categoria: 'internet',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.operacional,
    categoria: 'aluguel',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.operacional,
    categoria: 'energia',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.operacional,
    categoria: 'agua',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.operacional,
    categoria: 'contador',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.operacional,
    categoria: 'sistema',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.operacional,
    categoria: 'manutencao',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.operacional,
    categoria: 'limpeza',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.comercial,
    categoria: 'marketing',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.comercial,
    categoria: 'trafego_pago',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.comercial,
    categoria: 'influenciador',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.comercial,
    categoria: 'brindes',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.comercial,
    categoria: 'embalagens',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.comercial,
    categoria: 'divulgacao',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.estoque,
    categoria: 'compra_produtos',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.estoque,
    categoria: 'frete_mercadoria',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.estoque,
    categoria: 'reposicao',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.estoque,
    categoria: 'fornecedor',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.estrutura,
    categoria: 'moveis',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.estrutura,
    categoria: 'reforma',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.estrutura,
    categoria: 'filmagem',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.estrutura,
    categoria: 'iluminacao',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.estrutura,
    categoria: 'celular',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.estrutura,
    categoria: 'computador',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.estrutura,
    categoria: 'equipamentos',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.pessoas,
    categoria: 'funcionarios',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.pessoas,
    categoria: 'comissao',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.pessoas,
    categoria: 'ajuda_custo',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.pessoas,
    categoria: 'pro_labore',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.educacao,
    categoria: 'cursos',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.educacao,
    categoria: 'treinamentos',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.educacao,
    categoria: 'mentoria',
    subcategorias: [],
  ),
  FinanceiroCategoriaPadrao(
    grupo: FinanceiroGrupoCategoria.educacao,
    categoria: 'consultoria',
    subcategorias: [],
  ),
];

/// Categoria persistida desconhecida cai no primeiro item da lista padrao.
String financeiroCategoriaOuPadrao(String c) {
  final ok = kFinanceiroCategoriasPadrao.any((x) => x.categoria == c);
  return ok ? c : kFinanceiroCategoriasPadrao.first.categoria;
}
