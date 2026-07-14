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

  /// Contas a pagar (compras parceladas) — por loja.
  static String contasPagar(String lojaId) => 'contas_pagar_$lojaId';

  /// Lançamentos do módulo financeiro (complementar — por loja).
  static String lancamentosFinanceiros(String lojaId) =>
      'lancamentos_financeiros_$lojaId';

  /// Cadastro de gastos fixos mensais (sem geração automática nesta fase).
  static String gastosFixosMensais(String lojaId) => 'gastos_fixos_$lojaId';

  /// Lançamentos de compra por fornecedor (módulo interno; por loja).
  static String comprasFornecedor(String lojaId) => 'compras_fornecedor_$lojaId';

  /// Controle operacional de totais de compra por fornecedor (não entra em lucro/relatórios).
  static String controleTotaisCompraFornecedor(String lojaId) =>
      'controle_tot_compras_forn_$lojaId';

  /// Fila compra → precificação → estoque (por loja).
  static String compraItemPipeline(String lojaId) => 'compra_item_pipeline_$lojaId';

  /// Journal local de operationId pendente (recovery pré-Hive) — por loja.
  static String vendaOperationJournal(String lojaId) =>
      'venda_operation_journal_$lojaId';

  /// Atalhos / preferências da Home administrativa (favoritos, última categoria).
  static String homeUx(String lojaId) => 'home_ux_$lojaId';
}
