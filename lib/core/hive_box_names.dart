// lib/core/hive_box_names.dart
// Centraliza nomes de boxes Hive para evitar inconsistências e typos.

/// Nomes padronizados das boxes Hive por loja.
/// Use sempre estes helpers em vez de concatenar strings manualmente.
class HiveBoxNames {
  HiveBoxNames._();

  static String produtos(String lojaId) => 'produtos_$lojaId';
  static String clientes(String lojaId) => 'clientes_$lojaId';
  static String vendas(String lojaId) => 'vendas_$lojaId';
  static String fornecedores(String lojaId) => 'fornecedores_$lojaId';
  static String categorias(String lojaId) => 'categorias_$lojaId';
  static String subcategorias(String lojaId) => 'subcategorias_$lojaId';
  /// Box legado de EstoqueItem por loja (Excel import).
  static String estoque(String lojaId) => 'estoque_$lojaId';
  static String lojaConfig(String slug) => 'loja_config_$slug';
  static String configCatalogo() => 'config_catalogo';

  /// Config do catálogo POR LOJA (evita cache global entre lojas).
  static String configCatalogoLoja(String lojaId) => 'config_catalogo_$lojaId';
  static String config() => 'config';
  static String notaFiscalConfig(String lojaId) => 'nota_fiscal_config_$lojaId';
  static String notasFiscais(String lojaId) => 'notas_fiscais_$lojaId';
  static String relatorioFinanceiro(String lojaId) => 'loja_config_$lojaId';
  static String contasReceber(String lojaId) => 'contas_receber_$lojaId';
}
