// lib/services/permissao_service.dart
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'plano_service.dart';
import 'vendedor_service.dart';

class PermissaoService {
  // 🔑 Todas as chaves usadas no app (mantenha em sincronia com menus/telas)
  static const List<String> _todasAsChaves = [
    // Loja / Catálogo
    'catalogo_publico',
    'catalogo', // alias legado
    'minha_loja',
    'configuaracoes_catalogo', // (sic) mantém a mesma key usada nas rotas

    // Operação
    'estoque',
    'vendas',
    'clientes',
    'fornecedores',
    'precificacao',
    'notas_fiscais',

    // Relatórios
    'relatorios',
    'relatorio_financeiro',
    'historico_cliente',

    // Configurações
    'canais',
    'cupons',

    // Administração / Segurança
    'cadastro_usuarios',
    'licenca',
    'alterar_pin',
    'backup',
  ];

  /// Perfis padrão por tipo de usuário
  static const Map<String, Map<String, bool>> permissoesPadrao = {
    'programador': {
      'estoque': true,
      'vendas': true,
      'clientes': true,
      'fornecedores': true,
      'precificacao': true,
      'notas_fiscais': true,
      'relatorios': true,
      'historico_cliente': true,
      'cadastro_usuarios': true,
      'licenca': true,
      'alterar_pin': true,
      'backup': true,
      'catalogo': true,
      'catalogo_publico': true,
      'minha_loja': true,
      'configuaracoes_catalogo': true,
      'relatorio_financeiro': true,
      'canais': true,
      'cupons': true,
    },
    'admin': {
      'estoque': true,
      'vendas': true,
      'clientes': true,
      'fornecedores': true,
      'precificacao': true,
      'notas_fiscais': true,
      'relatorios': true,
      'historico_cliente': true,
      'cadastro_usuarios': true,
      'licenca': true,
      'alterar_pin': true,
      'backup': true,
      'catalogo': true,
      'catalogo_publico': true,
      'minha_loja': true,
      'configuaracoes_catalogo': true,
      'relatorio_financeiro': true,
      'canais': true,
      'cupons': true,
    },
    // ✅ VENDEDOR: Permissões MÍNIMAS padrão (admin libera dinamicamente)
    'vendedor': {
      'catalogo': false,          // ❌ Admin libera
      'catalogo_publico': false,  // ❌ Admin libera
      'minha_loja': false,        // ❌ NUNCA
      'configuaracoes_catalogo': false, // ❌ NUNCA
      'estoque': false,           // ❌ Admin libera
      'vendas': false,            // ❌ Admin libera
      'clientes': false,          // ❌ Admin libera
      'fornecedores': false,      // ❌ NUNCA
      'precificacao': false,      // ❌ NUNCA
      'notas_fiscais': false,     // ❌ NUNCA
      'relatorios': false,        // ❌ NUNCA
      'relatorio_financeiro': false, // ❌ NUNCA
      'historico_cliente': false, // ❌ Admin libera
      'cadastro_usuarios': false, // ❌ NUNCA
      'licenca': false,           // ❌ NUNCA
      'alterar_pin': false,       // ❌ NUNCA
      'backup': false,            // ❌ NUNCA
      'canais': false,            // ❌ NUNCA
      'cupons': false,            // ❌ NUNCA
      // ✅ Permissões sempre ativas para vendedor
      'meu_perfil': true,
      'minhas_comissoes': true,
      'meu_link': true,
    },
  };

  /// Permissões que VENDEDOR NUNCA pode ter (mesmo que admin tente liberar)
  static const List<String> _permissoesBloqueadasVendedor = [
    'pre_pedidos',
    'confirmar_compra',
    'valores_globais',
    'minha_loja',
    'configuaracoes_catalogo',
    'fornecedores',
    'precificacao',
    'notas_fiscais',
    'relatorios',
    'relatorio_financeiro',
    'cadastro_usuarios',
    'licenca',
    'alterar_pin',
    'backup',
    'canais',
    'cupons',
    'campanhas',
  ];

  /// 🔎 Usa plano individual (box: 'plano_ativo') se existir; senão, cai no perfil do tipo
  /// ✅ VENDEDOR: Carrega permissões dinâmicas do Firestore
  static Future<bool> possuiPermissao(String chave) async {
    final boxSessao = await Hive.openBox('sessao');
    final tipo = (boxSessao.get('tipo_usuario', defaultValue: 'vendedor') as String)
        .trim().toLowerCase();
    final email = boxSessao.get('usuario_logado', defaultValue: '');

    // ✅ VENDEDOR: Permissões bloqueadas SEMPRE retornam false
    if (tipo == 'vendedor' && _permissoesBloqueadasVendedor.contains(chave)) {
      return false;
    }

    // ✅ VENDEDOR: Carregar permissões dinâmicas do Firestore
    if (tipo == 'vendedor') {
      final permissoesDinamicas = await _carregarPermissoesVendedorFirestore();
      if (permissoesDinamicas.isNotEmpty) {
        return permissoesDinamicas[chave] ?? false;
      }
    }

    final plano = await _buscarPlanoUsuario(email);
    if (plano.isNotEmpty) {
      return plano[chave] ?? false;
    }

    final boxPermissoes = await Hive.openBox('permissoes');
    final Map<String, bool> permissoesTipo = Map<String, bool>.from(
      boxPermissoes.get(tipo, defaultValue: permissoesPadrao[tipo]) ?? {},
    );
    _garanteTodasAsChaves(permissoesTipo);
    return permissoesTipo[chave] ?? false;
  }

  /// ✅ Carrega permissões dinâmicas do vendedor via Firestore
  static Future<Map<String, bool>> _carregarPermissoesVendedorFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {};

      final boxSessao = await Hive.openBox('sessao');
      final storeId = (boxSessao.get('store_id') ?? boxSessao.get('storeId') ?? '').toString();
      if (storeId.isEmpty) return {};

      final vendedorService = VendedorService();
      final permissoes = await vendedorService.carregarPermissoes(user.uid, storeId);

      // ✅ Garantir bloqueadas
      for (final b in _permissoesBloqueadasVendedor) {
        permissoes[b] = false;
      }

      debugPrint('✅ [PERMISSAO] Vendedor permissões carregadas: ${permissoes.keys.where((k) => permissoes[k] == true).toList()}');
      return permissoes;
    } catch (e) {
      debugPrint('⚠️ [PERMISSAO] Erro ao carregar permissões vendedor (type=${e.runtimeType})');
      return {};
    }
  }

  /// ✅ Verifica se vendedor tem ALGUMA permissão liberada
  static Future<bool> vendedorTemAlgumaPermissao() async {
    final boxSessao = await Hive.openBox('sessao');
    final tipo = (boxSessao.get('tipo_usuario', defaultValue: 'vendedor') as String)
        .trim().toLowerCase();

    if (tipo != 'vendedor') return true; // Admin/programador sempre tem

    final permissoes = await _carregarPermissoesVendedorFirestore();

    // Verifica se tem pelo menos uma permissão liberável
    final liberaveis = ['catalogo', 'vendas', 'estoque', 'clientes', 'historico_cliente'];
    for (final p in liberaveis) {
      if (permissoes[p] == true) return true;
    }

    return false;
  }

  /// 🔁 Retorna todas as permissões resolvidas (plano individual > tipo)
  static Future<Map<String, bool>> todas() async {
    final boxSessao = await Hive.openBox('sessao');
    final email = boxSessao.get('usuario_logado', defaultValue: '');
    final tipo = boxSessao.get('tipo_usuario', defaultValue: 'vendedor');

    final plano = await _buscarPlanoUsuario(email);
    if (plano.isNotEmpty) {
      _garanteTodasAsChaves(plano);
      return plano;
    }

    final boxPermissoes = await Hive.openBox('permissoes');
    final Map<String, bool> permissoesTipo = Map<String, bool>.from(
      boxPermissoes.get(tipo, defaultValue: permissoesPadrao[tipo]) ?? {},
    );
    _garanteTodasAsChaves(permissoesTipo);
    return permissoesTipo;
  }

  /// 🎯 Pega/salva plano individual (por e-mail) — armazenamento local (Hive)
  static Future<Map<String, bool>> getPermissoesPorUsuario(String email) async {
    final boxPlano = await Hive.openBox('plano_ativo');
    final plano = boxPlano.get(email);
    if (plano is Map) {
      final map = Map<String, bool>.from(plano);
      _garanteTodasAsChaves(map);
      return map;
    }
    return {};
  }

  static Future<void> salvarPermissoesPorUsuario(
      String email, Map<String, bool> permissoes) async {
    _garanteTodasAsChaves(permissoes);
    final box = await Hive.openBox('plano_ativo');
    await box.put(email, permissoes);
  }

  /// ♻️ Restaura permissões padrão do tipo do usuário logado (somente na box 'permissoes')
  static Future<void> restaurarPadrao() async {
    final boxSessao = await Hive.openBox('sessao');
    final tipo = boxSessao.get('tipo_usuario', defaultValue: 'vendedor');
    final padrao = Map<String, bool>.from(permissoesPadrao[tipo] ?? {});
    _garanteTodasAsChaves(padrao);

    final boxPerm = await Hive.openBox('permissoes');
    await boxPerm.put(tipo, padrao);
  }

  // ===================== Suporte ao bootstrap =====================

  /// ✅ Garante que a box 'permissoes' tenha um perfil base para o tipo atual.
  ///    Não mexe na box 'plano_ativo' (planos individuais).
  static Future<void> refreshPermissoesLocais() async {
    final sessao = await Hive.openBox('sessao');
    final tipo =
        (sessao.get('tipo_usuario', defaultValue: 'vendedor') as String)
            .trim()
            .toLowerCase();

    final boxPerm = await Hive.openBox('permissoes');

    final Map<String, bool> atual = Map<String, bool>.from(
      boxPerm.get(tipo, defaultValue: permissoesPadrao[tipo]) ?? {},
    );

    _garanteTodasAsChaves(atual);
    await boxPerm.put(tipo, atual);
  }

  /// 🔄 (Opcional) Sincroniza plano do usuário logado a partir do Firestore (por UID),
  ///     salva em 'plano_ativo' (chave = e-mail) e mantém compatibilidade com as telas.
  static Future<void> syncFromRemoteIfAny() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Busca plano remoto por UID (conforme suas rules)
    final remoto = await PlanoService.getPlanoByUid(user.uid);
    if (remoto.isEmpty) return;

    final email = user.email ?? '';
    if (email.isEmpty) return;

    // Salva plano remoto na store local por e-mail (mantendo compatibilidade)
    await salvarPermissoesPorUsuario(email, remoto);

    // Atualiza caixa 'permissoes' baseada no tipo atual (não sobrescreve 'plano_ativo')
    await refreshPermissoesLocais();
  }

  // ===================== Internos =====================

  static void _garanteTodasAsChaves(Map<String, bool> map) {
    for (final k in _todasAsChaves) {
      map.putIfAbsent(k, () => false);
    }
  }

  static Future<Map<String, bool>> _buscarPlanoUsuario(String email) async {
    if (email.trim().isEmpty) return {};
    final box = await Hive.openBox('plano_ativo');
    final plano = box.get(email);
    if (plano is Map) {
      final map = Map<String, bool>.from(plano);
      _garanteTodasAsChaves(map);
      return map;
    }
    return {};
  }
}
