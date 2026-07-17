// M3.8 SPRINT3-MULTIUSUARIO-R2 — escopo de acesso Admin × Vendedor (camada app).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/venda.dart';
import '../utils/role_utils.dart';

/// Snapshot imutável do sujeito autenticado para filtros de isolamento.
@immutable
class AccessScopeIdentity {
  const AccessScopeIdentity({
    required this.role,
    required this.uid,
    required this.email,
    required this.displayName,
  });

  final UserRole role;
  final String uid;
  final String email;
  final String displayName;

  bool get isAdmin =>
      role == UserRole.admin || role == UserRole.programador;

  bool get isSeller => role == UserRole.vendedor;

  /// Chaves legadas (e-mail / nome) — só fallback quando `vendedorUid` ausente.
  Set<String> get sellerKeys {
    final keys = <String>{};
    void add(String? raw) {
      final t = (raw ?? '').trim().toLowerCase();
      if (t.isNotEmpty) keys.add(t);
    }

    add(uid);
    add(email);
    add(displayName);
    if (displayName.contains(' ')) {
      add(displayName.split(RegExp(r'\s+')).first);
    }
    return keys;
  }
}

/// Camada centralizada de isolamento multiusuário.
///
/// Admin/programador: vê tudo da loja.
/// Vendedor: vê apenas dados próprios (exceto pesquisa global na Nova Venda).
/// Chave oficial de venda: `vendedorUid` (fallback: e-mail → nome → legado).
abstract final class AccessScopeService {
  AccessScopeService._();

  static const logTag = '[M38-MULTI]';

  /// Carrega identidade a partir da sessão Hive + Auth.
  static Future<AccessScopeIdentity> loadIdentity() async {
    final role = await RoleUtils.loadFromSession();
    final auth = FirebaseAuth.instance.currentUser;
    var email = (auth?.email ?? '').trim().toLowerCase();
    var uid = (auth?.uid ?? '').trim();
    var nome = (auth?.displayName ?? '').trim();

    try {
      final sessao = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');
      final login = (sessao.get('usuario_logado') ?? '').toString().trim();
      if (email.isEmpty && login.contains('@')) {
        email = login.toLowerCase();
      }
      final vUid = (sessao.get('vendedor_uid') ?? '').toString().trim();
      if (uid.isEmpty && vUid.isNotEmpty) uid = vUid;
      final vNome = (sessao.get('vendedor_nome') ?? '').toString().trim();
      if (nome.isEmpty && vNome.isNotEmpty) nome = vNome;
      if (nome.isEmpty && login.isNotEmpty && !login.contains('@')) {
        nome = login;
      }
    } catch (e) {
      debugPrint('$logTag loadIdentity session err type=${e.runtimeType}');
    }

    return AccessScopeIdentity(
      role: role,
      uid: uid,
      email: email,
      displayName: nome,
    );
  }

  static bool isAdmin(AccessScopeIdentity id) => id.isAdmin;
  static bool isSeller(AccessScopeIdentity id) => id.isSeller;
  static String currentSellerId(AccessScopeIdentity id) => id.uid;
  static String currentSellerUid(AccessScopeIdentity id) => id.uid;

  /// Admin vê tudo; vendedor só vendas atribuídas a si.
  static bool canSeeSale(AccessScopeIdentity id, Venda sale) {
    if (id.isAdmin) return true;
    return sellerOwnsSale(sale, id);
  }

  /// Alias oficial R2.
  static bool sellerOwnsSale(Venda sale, AccessScopeIdentity id) =>
      saleBelongsToSeller(sale, id);

  /// Pesquisa global na Nova Venda (evita cliente duplicado).
  static bool canSearchAllCustomersInSale(AccessScopeIdentity id) => true;

  /// Na Nova Venda, ao selecionar cliente: não expor CRM/histórico alheio.
  static bool canSeeCustomerPrivateCrm(AccessScopeIdentity id) => id.isAdmin;

  /// Lista de clientes (carteira N:N): admin todos; vendedor só carteira.
  static bool canSeeCustomer({
    required AccessScopeIdentity id,
    required String customerKey,
    required Set<String> walletCustomerKeys,
  }) =>
      canSeeCustomerInList(
        id: id,
        customerKey: customerKey,
        walletCustomerKeys: walletCustomerKeys,
      );

  static bool canSeeCustomerInList({
    required AccessScopeIdentity id,
    required String customerKey,
    required Set<String> walletCustomerKeys,
  }) {
    if (id.isAdmin) return true;
    final k = _norm(customerKey);
    if (k.isEmpty) return false;
    return walletCustomerKeys.contains(k);
  }

  static bool canSeeHistory(AccessScopeIdentity id, Venda sale) =>
      canSeeSale(id, sale);

  static bool canSeeHistorySale(AccessScopeIdentity id, Venda sale) =>
      canSeeHistory(id, sale);

  static bool canSeeDashboard(AccessScopeIdentity id) => true;

  /// Acesso à rota/tela `/vendas` (lista + pesquisa + detalhes no escopo).
  /// Independente de indicadores globais — vendedor SEMPRE pode abrir a tela;
  /// o isolamento de linhas usa [canSeeSale] / [filterSalesForScope].
  static bool canAccessVendasScreen(AccessScopeIdentity id) => true;

  /// Consolidados da loja (bruto/líquido/lucro/ticket/Qtd total/mais vendidos…).
  /// Sprint4-R2: somente admin/programador.
  static bool canSeeStoreAggregates(AccessScopeIdentity id) => id.isAdmin;

  /// KPIs/indicadores consolidados da loja na UX de Vendas (mês/ano/resumo…).
  /// Diferente de [canAccessVendasScreen].
  static bool canSeeVendasStoreKpis(AccessScopeIdentity id) =>
      canSeeStoreAggregates(id);

  /// Resumo de vendas (sheet/rota) — dados globais da loja.
  static bool canSeeVendasResumoGlobal(AccessScopeIdentity id) =>
      canSeeStoreAggregates(id);

  /// Tela/ranking "Mais vendidos" com faturamento — admin only nesta fase.
  static bool canSeeMaisVendidos(AccessScopeIdentity id) =>
      canSeeStoreAggregates(id);

  /// Totais consolidados no header do Estoque (valor de venda / custo / …).
  static bool canSeeStockFinancialTotals(AccessScopeIdentity id) =>
      canSeeStoreAggregates(id);

  /// Hub Financeiro & Metas da loja (não a tela pessoal Metas & Comissões).
  static bool canSeeFinanceiroMetasLoja(AccessScopeIdentity id) =>
      canSeeStoreAggregates(id);

  /// Relatório/exportação com escopo: admin=loja; vendedor=próprias vendas
  /// (filtrar via [filterSalesForScope]). Agregados de loja usam
  /// [canSeeStoreAggregates].
  static bool canSeeReport(AccessScopeIdentity id) => true;

  static bool canExport(AccessScopeIdentity id) => true;

  static bool canSeeFinancial(AccessScopeIdentity id) => id.isAdmin;

  static bool canAccessFinanceiro(AccessScopeIdentity id) =>
      canSeeFinancial(id);

  /// Cadastro/edição/exclusão/ajuste de inventário — somente admin/programador.
  /// Independente de [canConsultStock] (consulta qty/preço).
  static bool canManageStock(AccessScopeIdentity id) => id.isAdmin;

  static bool canEditStock(AccessScopeIdentity id) => canManageStock(id);

  /// Operações administrativas de clientes (importação, reset de senha do catálogo).
  static bool canManageCustomers(AccessScopeIdentity id) => id.isAdmin;

  static bool canImportClients(AccessScopeIdentity id) =>
      canManageCustomers(id);

  static bool canResetClienteCatalogPassword(AccessScopeIdentity id) =>
      canManageCustomers(id);

  /// Consulta de estoque (qty + preço de venda). Vendedor: sim.
  static bool canConsultStock(AccessScopeIdentity id) => true;

  /// Custo / margem / fornecedor / movimentações — nunca para vendedor nesta fase.
  static bool canSeeStockCostAndSupplier(AccessScopeIdentity id) => id.isAdmin;

  static bool canManageCampaigns(AccessScopeIdentity id) => id.isAdmin;

  static bool canUseMarketingTools(AccessScopeIdentity id) => true;

  static bool customerBelongsToSeller({
    required AccessScopeIdentity id,
    required String customerKey,
    required Set<String> walletCustomerKeys,
  }) {
    if (id.isAdmin) return true;
    return walletCustomerKeys.contains(_norm(customerKey));
  }

  /// Carteira N:N — cliente com ≥1 venda do vendedor (nunca vínculo exclusivo).
  static Set<String> buildSellerWalletKeys({
    required AccessScopeIdentity id,
    required Iterable<Venda> sales,
    required String? lojaId,
  }) {
    final keys = <String>{};
    for (final v in sales) {
      if (!_saleInStore(v, lojaId)) continue;
      if (!sellerOwnsSale(v, id)) continue;
      final cid = (v.clienteId ?? '').trim();
      if (cid.isNotEmpty) keys.add(_norm(cid));
      final nome = v.clienteNome.trim();
      if (nome.isNotEmpty) keys.add(_norm(nome));
    }
    return keys;
  }

  /// Match oficial: `vendedorUid` → `vendedorEmail` → `vendedorNome` → legado `vendedor`.
  static bool saleBelongsToSeller(Venda sale, AccessScopeIdentity id) {
    final uid = _norm(sale.vendedorUid);
    if (uid.isNotEmpty) {
      final mine = _norm(id.uid);
      return mine.isNotEmpty && uid == mine;
    }

    final email = _norm(sale.vendedorEmail);
    if (email.isNotEmpty) {
      final mine = _norm(id.email);
      return mine.isNotEmpty && email == mine;
    }

    final nome = _norm(sale.vendedorNome);
    if (nome.isNotEmpty) {
      return id.sellerKeys.contains(nome);
    }

    final legacy = _norm(sale.vendedor);
    if (legacy.isEmpty) return false;
    return id.sellerKeys.contains(legacy);
  }

  /// Mapas Firestore / dumps: mesma ordem de prioridade.
  static bool mapSaleBelongsToSeller(
    Map<String, dynamic> data,
    AccessScopeIdentity id,
  ) {
    final uid = _norm(
      (data['vendedorUid'] ?? data['vendedorId'] ?? data['sellerUid'])
          ?.toString(),
    );
    if (uid.isNotEmpty) {
      final mine = _norm(id.uid);
      return mine.isNotEmpty && uid == mine;
    }

    final email = _norm(
      (data['vendedorEmail'] ?? data['sellerEmail'])?.toString(),
    );
    if (email.isNotEmpty) {
      final mine = _norm(id.email);
      return mine.isNotEmpty && email == mine;
    }

    final nome = _norm(
      (data['vendedorNome'] ?? data['sellerName'])?.toString(),
    );
    if (nome.isNotEmpty) {
      return id.sellerKeys.contains(nome);
    }

    final legacy = _norm(data['vendedor']?.toString());
    if (legacy.isEmpty) return false;
    return id.sellerKeys.contains(legacy);
  }

  /// Preferência de origem: vendas com uid → filtro por uid; legado em segundo passo.
  static List<Venda> filterSalesForScope({
    required AccessScopeIdentity id,
    required Iterable<Venda> sales,
    String? lojaId,
  }) {
    if (id.isAdmin) {
      return sales
          .where((v) => _saleInStore(v, lojaId))
          .toList(growable: false);
    }
    final uid = _norm(id.uid);
    final withUid = <Venda>[];
    final legacy = <Venda>[];
    for (final v in sales) {
      if (!_saleInStore(v, lojaId)) continue;
      final vu = _norm(v.vendedorUid);
      if (vu.isNotEmpty) {
        if (uid.isNotEmpty && vu == uid) withUid.add(v);
      } else if (sellerOwnsSale(v, id)) {
        legacy.add(v);
      }
    }
    return [...withUid, ...legacy];
  }

  static List<Venda> filterCustomerHistory({
    required AccessScopeIdentity id,
    required Iterable<Venda> sales,
    required String? lojaId,
    required String customerName,
    String? customerId,
  }) {
    final nome = _norm(customerName);
    final cid = _norm(customerId);
    return filterSalesForScope(id: id, sales: sales, lojaId: lojaId)
        .where((v) {
          final sameId = cid.isNotEmpty && _norm(v.clienteId) == cid;
          final sameName = nome.isNotEmpty && _norm(v.clienteNome) == nome;
          return sameId || sameName;
        })
        .toList(growable: false);
  }

  /// Carrinho: atribuído ao vendedor OU cliente da carteira.
  /// Sem responsável e sem cliente de carteira → apenas admin (MULTI-15).
  static bool canSeeCart({
    required AccessScopeIdentity id,
    required Set<String> walletCustomerKeys,
    String? createdByUid,
    String? createdByEmail,
    String? assignedSellerUid,
    String? customerKey,
    String? customerName,
  }) {
    if (id.isAdmin) return true;

    final byUid = _norm(createdByUid);
    final byEmail = _norm(createdByEmail);
    final assigned = _norm(assignedSellerUid);

    if (assigned.isNotEmpty && assigned == _norm(id.uid)) return true;
    if (byUid.isNotEmpty &&
        (byUid == _norm(id.uid) || id.sellerKeys.contains(byUid))) {
      return true;
    }
    if (byEmail.isNotEmpty && id.sellerKeys.contains(byEmail)) return true;

    final ck = _norm(customerKey);
    final cn = _norm(customerName);
    if (ck.isNotEmpty && walletCustomerKeys.contains(ck)) return true;
    if (cn.isNotEmpty && walletCustomerKeys.contains(cn)) return true;

    // Sem atribuição e sem cliente de carteira → não mostra ao vendedor.
    return false;
  }

  /// Plano pertence SOMENTE à loja — nunca individual do vendedor.
  static bool sellerRequiresIndividualPlan() => false;

  static bool shouldWritePlanFieldsOnSellerUserDoc() => false;

  static bool planBelongsToStoreOnly() => true;

  /// Quick actions da Home para vendedor.
  static const sellerHomeQuickActionIds = <String>[
    'catalogo_interno',
    'clientes',
    'catalogo_loja',
    'vendas',
  ];

  static const adminHomeQuickActionIds = <String>[
    'vendas',
    'estoque',
    'clientes',
    'catalogo_loja',
  ];

  static List<String> homeQuickActionIds(AccessScopeIdentity id) =>
      id.isSeller ? sellerHomeQuickActionIds : adminHomeQuickActionIds;

  /// Label de pesquisa global (Nova Venda).
  static String customerSearchSubtitle({
    required String? telefone,
    required String? cidade,
    required String? cpf,
    required String? endereco,
  }) {
    final parts = <String>[];
    void add(String? v) {
      final t = (v ?? '').trim();
      if (t.isNotEmpty) parts.add(t);
    }

    add(telefone);
    add(cidade);
    add(cpf);
    add(endereco);
    return parts.join(' · ');
  }

  static bool _saleInStore(Venda v, String? lojaId) {
    if (lojaId == null || lojaId.trim().isEmpty) return true;
    final lid = (v.lojaId ?? '').trim();
    return lid.isEmpty || lid == lojaId;
  }

  static String _norm(String? raw) => (raw ?? '').trim().toLowerCase();
}
