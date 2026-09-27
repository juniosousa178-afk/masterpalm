// Roteador do hub operacional. Não persiste lançamento, compra, conta ou ledger.

import '../financeiro_constants.dart';

enum FinancialHubNavigation {
  namedRoute,
  existingLancamento,
  existingFixedExpenses,
}

/// Destino de uma ação ou atalho. [persists] fica falso: quem grava é a tela antiga.
class FinancialHubDestination {
  const FinancialHubDestination({
    required this.id,
    required this.label,
    required this.helper,
    required this.navigation,
    required this.screen,
    required this.service,
    this.route,
    this.tipoLancamento,
    this.categoria,
    this.openNewForm = false,
    this.showFilters = false,
    this.persists = false,
  });

  final String id;
  final String label;
  final String helper;
  final FinancialHubNavigation navigation;
  final String screen;
  final String service;
  final String? route;
  final String? tipoLancamento;
  final String? categoria;
  final bool openNewForm;
  final bool showFilters;
  final bool persists;
}

/// Categoria de embalagens já existente. O hub não cria outra.
const String financialExistingPackagingCategory = 'embalagens';

abstract final class FinancialLaunchCatalog {
  static const bool createsFinancialRecord = false;
  static const int ledgerWrites = 0;

  static const FinancialHubDestination compraMercadoria = FinancialHubDestination(
    id: 'compra_mercadoria',
    label: 'Compra de mercadoria',
    helper: 'Para produtos comprados para revenda.',
    navigation: FinancialHubNavigation.namedRoute,
    route: '/fornecedores',
    screen:
        'FornecedoresScreen → FornecedorComprasScreen → CompraFornecedorFormScreen',
    service: 'CompraFornecedor + ContaPagarService.gerarParcelasCompra',
  );

  static const FinancialHubDestination despesa = FinancialHubDestination(
    id: 'despesa',
    label: 'Despesa',
    helper: 'Embalagens, fretes, marketing e outras despesas da operação.',
    navigation: FinancialHubNavigation.existingLancamento,
    screen: 'FinanceiroLancamentosScreen',
    service: 'FinanceiroFirestoreService.upsertLancamento',
    tipoLancamento: FinanceiroTipoLancamento.despesaOperacional,
    openNewForm: true,
  );

  static const FinancialHubDestination contaPagar = FinancialHubDestination(
    id: 'conta_pagar',
    label: 'Conta a pagar',
    helper: 'Para registrar um compromisso com vencimento futuro.',
    navigation: FinancialHubNavigation.namedRoute,
    route: '/contas_pagar',
    screen: 'ContasPagarScreen',
    service: 'ContaPagarService',
  );

  static const FinancialHubDestination gastoRecorrente = FinancialHubDestination(
    id: 'gasto_recorrente',
    label: 'Gasto recorrente',
    helper: 'Aluguel, internet, contador e outras contas que se repetem.',
    navigation: FinancialHubNavigation.existingFixedExpenses,
    screen: 'GastosFixosScreen',
    service: 'GastoFixoLancamentoService',
  );

  static const FinancialHubDestination entradaExtra = FinancialHubDestination(
    id: 'entrada_extra',
    label: 'Entrada extra',
    helper:
        'Valores recebidos que não vieram de uma venda. Não registre aqui venda em Pix, dinheiro, cartão ou baixa de fiado.',
    navigation: FinancialHubNavigation.existingLancamento,
    screen: 'FinanceiroLancamentosScreen',
    service: 'FinanceiroFirestoreService.upsertLancamento',
    tipoLancamento: FinanceiroTipoLancamento.entradaExtra,
    openNewForm: true,
  );

  static const FinancialHubDestination salario = FinancialHubDestination(
    id: 'salario',
    label: 'Salário / equipe',
    helper: 'Registro financeiro de pagamento da equipe. Não é folha de pagamento.',
    navigation: FinancialHubNavigation.existingLancamento,
    screen: 'FinanceiroLancamentosScreen',
    service: 'FinanceiroFirestoreService.upsertLancamento',
    tipoLancamento: FinanceiroTipoLancamento.pagamentoFuncionario,
    openNewForm: true,
  );

  static const FinancialHubDestination proLabore = FinancialHubDestination(
    id: 'pro_labore',
    label: 'Pró-labore',
    helper:
        'Pagamento do sócio pelo trabalho. Não é salário, despesa comum nem retirada.',
    navigation: FinancialHubNavigation.existingLancamento,
    screen: 'FinanceiroLancamentosScreen',
    service: 'FinanceiroFirestoreService.upsertLancamento',
    tipoLancamento: FinanceiroTipoLancamento.proLabore,
    openNewForm: true,
  );

  static const FinancialHubDestination retirada = FinancialHubDestination(
    id: 'retirada',
    label: 'Retirada',
    helper: 'Retirada do sócio. Não entra como despesa da operação.',
    navigation: FinancialHubNavigation.existingLancamento,
    screen: 'FinanceiroLancamentosScreen',
    service: 'FinanceiroFirestoreService.upsertLancamento',
    tipoLancamento: FinanceiroTipoLancamento.retirada,
    openNewForm: true,
  );

  static const FinancialHubDestination investimento = FinancialHubDestination(
    id: 'investimento',
    label: 'Investimento',
    helper: 'Móveis, equipamentos e melhorias da loja. Não é despesa do dia a dia.',
    navigation: FinancialHubNavigation.existingLancamento,
    screen: 'FinanceiroLancamentosScreen',
    service: 'FinanceiroFirestoreService.upsertLancamento',
    tipoLancamento: FinanceiroTipoLancamento.investimento,
    openNewForm: true,
  );

  static const List<FinancialHubDestination> options = [
    compraMercadoria,
    despesa,
    contaPagar,
    gastoRecorrente,
    entradaExtra,
    salario,
    proLabore,
    retirada,
    investimento,
  ];

  static const FinancialHubDestination lancamentos = FinancialHubDestination(
    id: 'lancamentos',
    label: 'Lançamentos',
    helper: 'Lançamentos já registrados nesta loja.',
    navigation: FinancialHubNavigation.existingLancamento,
    screen: 'FinanceiroLancamentosScreen',
    service: 'FinanceiroHiveStore',
    showFilters: true,
  );

  static const FinancialHubDestination receber = FinancialHubDestination(
    id: 'receber',
    label: 'A receber',
    helper: 'Contas a receber e fiado já existentes.',
    navigation: FinancialHubNavigation.namedRoute,
    route: '/contas_receber',
    screen: 'ContasReceberScreen',
    service: 'ContaReceberService',
  );

  static const FinancialHubDestination pagar = FinancialHubDestination(
    id: 'pagar',
    label: 'A pagar',
    helper: 'Contas a pagar deste dispositivo.',
    navigation: FinancialHubNavigation.namedRoute,
    route: '/contas_pagar',
    screen: 'ContasPagarScreen',
    service: 'ContaPagarService',
  );

  static const FinancialHubDestination compras = FinancialHubDestination(
    id: 'compras',
    label: 'Compras',
    helper: 'Compras de fornecedor já existentes.',
    navigation: FinancialHubNavigation.namedRoute,
    route: '/fornecedores',
    screen:
        'FornecedoresScreen → FornecedorComprasScreen → CompraFornecedorFormScreen',
    service: 'CompraFornecedor + ContaPagarService.gerarParcelasCompra',
  );

  static const FinancialHubDestination gastosFixos = FinancialHubDestination(
    id: 'gastos_fixos',
    label: 'Gastos fixos',
    helper: 'Gastos recorrentes já cadastrados.',
    navigation: FinancialHubNavigation.existingFixedExpenses,
    screen: 'GastosFixosScreen',
    service: 'GastoFixoLancamentoService',
  );

  static const FinancialHubDestination relatorios = FinancialHubDestination(
    id: 'relatorios',
    label: 'Relatórios',
    helper: 'Relatórios financeiros já existentes.',
    navigation: FinancialHubNavigation.namedRoute,
    route: '/relatorios_financeiros',
    screen: 'RelatoriosFinanceirosScreen',
    service: 'RelatoriosFinanceirosScreen',
  );

  static const List<FinancialHubDestination> shortcuts = [
    lancamentos,
    receber,
    pagar,
    compras,
    gastosFixos,
    relatorios,
  ];

  static FinancialHubDestination byId(String id) {
    for (final item in options) {
      if (item.id == id) return item;
    }
    for (final item in shortcuts) {
      if (item.id == id) return item;
    }
    throw ArgumentError('Destino financeiro desconhecido: $id');
  }
}

/// O hub só navega. O painel só leitura não grava, mesmo com o hub ligado.
abstract final class FinancialV2OperationalPolicy {
  static const int directFinancialWrites = 0;

  static bool hubEnabled({
    required bool showReadOnlyDashboard,
    required bool operationalHubEnabled,
  }) =>
      showReadOnlyDashboard && operationalHubEnabled;
}
