// lib/services/vendedor_service.dart
// Serviço centralizado para gerenciamento de vendedores
// Multi-tenant: vendedor SEMPRE vinculado a UMA loja (storeId do admin)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';

/// Modelo de perfil do vendedor (Firestore)
class VendedorPerfil {
  final String uid;
  final String email;
  final String nome;
  final String telefone;
  final String storeId;          // ✅ Loja vinculada (OBRIGATÓRIO)
  final String adminUid;          // UID do admin que cadastrou
  final String adminEmail;        // Email do admin
  final bool ativo;               // Se o vendedor está ativo
  final Map<String, bool> permissoes; // Permissões dinâmicas
  final double? comissaoPercentual;   // null = usa global da loja
  final DateTime criadoEm;
  final DateTime? atualizadoEm;

  VendedorPerfil({
    required this.uid,
    required this.email,
    required this.nome,
    this.telefone = '',
    required this.storeId,
    required this.adminUid,
    required this.adminEmail,
    this.ativo = true,
    this.permissoes = const {},
    this.comissaoPercentual,
    required this.criadoEm,
    this.atualizadoEm,
  });

  factory VendedorPerfil.fromFirestore(Map<String, dynamic> data, String uid) {
    return VendedorPerfil(
      uid: uid,
      email: (data['email'] ?? '').toString().trim().toLowerCase(),
      nome: (data['nome'] ?? data['name'] ?? '').toString(),
      telefone: (data['telefone'] ?? data['phone'] ?? '').toString(),
      storeId: (data['storeId'] ?? data['store_id'] ?? data['lojaId'] ?? '').toString(),
      adminUid: (data['adminUid'] ?? data['ownerId'] ?? data['createdBy'] ?? '').toString(),
      adminEmail: (data['adminEmail'] ?? data['ownerEmail'] ?? data['ownerAdminEmail'] ?? '').toString(),
      ativo: _parseBool(data['ativo'] ?? data['active'] ?? true),
      permissoes: _parsePermissoes(data['permissoes'] ?? data['permissions']),
      comissaoPercentual: (data['comissaoPercentual'] as num?)?.toDouble(),
      criadoEm: _parseTimestamp(data['criadoEm'] ?? data['createdAt']),
      atualizadoEm: _parseTimestamp(data['atualizadoEm'] ?? data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'nome': nome,
      'telefone': telefone,
      'storeId': storeId,
      'adminUid': adminUid,
      'adminEmail': adminEmail,
      'ativo': ativo,
      'permissoes': permissoes,
      'comissaoPercentual': comissaoPercentual,
      'criadoEm': Timestamp.fromDate(criadoEm),
      'atualizadoEm': FieldValue.serverTimestamp(),
      'role': 'vendedor',
      'tipo': 'vendedor',
    };
  }

  /// Firestore às vezes grava bool como 1/0 — evita TypeError em runtime (Web minificado).
  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'sim';
    }
    return true;
  }

  static Map<String, bool> _parsePermissoes(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map) {
      return Map<String, bool>.from(
        raw.map(
          (k, v) => MapEntry(
            k.toString(),
            v == true || v == 1 || v == '1' || v == 'true',
          ),
        ),
      );
    }
    return {};
  }

  static DateTime _parseTimestamp(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.now();
  }

  /// Verifica se tem permissão específica
  bool temPermissao(String key) {
    return permissoes[key] == true;
  }

  /// Copia com alterações
  VendedorPerfil copyWith({
    bool? ativo,
    Map<String, bool>? permissoes,
    double? comissaoPercentual,
  }) {
    return VendedorPerfil(
      uid: uid,
      email: email,
      nome: nome,
      telefone: telefone,
      storeId: storeId,
      adminUid: adminUid,
      adminEmail: adminEmail,
      ativo: ativo ?? this.ativo,
      permissoes: permissoes ?? this.permissoes,
      comissaoPercentual: comissaoPercentual ?? this.comissaoPercentual,
      criadoEm: criadoEm,
      atualizadoEm: DateTime.now(),
    );
  }
}

/// Serviço centralizado para vendedores
class VendedorService {
  static final VendedorService _instance = VendedorService._internal();
  factory VendedorService() => _instance;
  VendedorService._internal();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Cache do perfil atual
  VendedorPerfil? _perfilAtual;
  VendedorPerfil? get perfilAtual => _perfilAtual;

  /// Permissões padrão de vendedor (todas desativadas até admin liberar)
  static const Map<String, bool> permissoesPadrao = {
    'catalogo': false,
    'vendas': false,
    'estoque': false,
    'clientes': false,
    'historico_cliente': false,
    'meu_perfil': true,           // Sempre pode ver próprio perfil
    'minhas_comissoes': true,     // Sempre pode ver próprias comissões
    'meu_link': true,             // Sempre pode ver/copiar link
  };

  /// Permissões que admin pode liberar para vendedor
  static const List<String> permissoesLiberaveis = [
    'catalogo',
    'vendas',
    'estoque',
    'clientes',
    'historico_cliente',
  ];

  /// Permissões que vendedor NUNCA pode ter
  static const List<String> permissoesBloqueadas = [
    'pre_pedidos',              // ❌ NUNCA
    'confirmar_compra',         // ❌ NUNCA
    'relatorios',               // ❌ NUNCA
    'relatorio_financeiro',     // ❌ NUNCA
    'financeiro',               // ❌ NUNCA (modulo gestao financeira)
    'valores_globais',          // ❌ NUNCA
    'precificacao',             // ❌ NUNCA
    'fornecedores',             // ❌ NUNCA
    'cadastro_usuarios',        // ❌ NUNCA
    'configuracoes',            // ❌ NUNCA
    'licenca',                  // ❌ NUNCA
    'backup',                   // ❌ NUNCA
    'canais',                   // ❌ NUNCA
    'cupons',                   // ❌ NUNCA
    'campanhas',                // ❌ NUNCA
  ];

  // ==========================================================================
  // CARREGAMENTO E CACHE
  // ==========================================================================

  /// Carrega perfil do vendedor logado
  Future<VendedorPerfil?> carregarPerfilAtual() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      // Buscar em lojas/{storeId}/vendedores/{uid}
      // Primeiro, descobrir o storeId via users/{uid}
      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return null;

      final userData = userDoc.data() ?? {};
      final role = (userData['role'] ?? userData['tipo'] ?? '').toString().toLowerCase();

      if (role != 'vendedor') return null;

      final storeId = (userData['storeId'] ?? userData['store_id'] ?? userData['lojaId'] ?? '').toString();
      if (storeId.isEmpty) return null;

      // Buscar perfil completo em lojas/{storeId}/vendedores/{uid}
      final vendedorDoc = await _db
          .collection('lojas')
          .doc(storeId)
          .collection('vendedores')
          .doc(user.uid)
          .get();

      if (vendedorDoc.exists) {
        _perfilAtual = VendedorPerfil.fromFirestore(
          vendedorDoc.data() ?? {},
          user.uid,
        );
      } else {
        // Fallback: criar perfil básico a partir de users/{uid}
        _perfilAtual = VendedorPerfil.fromFirestore(userData, user.uid);
      }

      return _perfilAtual;
    } catch (e) {
      debugPrint('❌ [VENDEDOR] Erro ao carregar perfil (type=${e.runtimeType})');
      return null;
    }
  }

  /// Limpa cache (logout)
  void limparCache() {
    _perfilAtual = null;
  }

  // ==========================================================================
  // VALIDAÇÕES MULTI-TENANT
  // ==========================================================================

  /// Verifica se vendedor pertence à loja
  Future<bool> vendedorPertenceALoja(String vendedorUid, String storeId) async {
    try {
      final doc = await _db
          .collection('lojas')
          .doc(storeId)
          .collection('vendedores')
          .doc(vendedorUid)
          .get();

      return doc.exists && (doc.data()?['ativo'] ?? false) == true;
    } catch (e) {
      debugPrint('⚠️ [VENDEDOR] Erro ao validar pertencimento (type=${e.runtimeType})');
      return false;
    }
  }

  /// Valida que vendedor só acessa sua loja (anti-fraude)
  Future<bool> validarAcessoLoja(String storeIdRequisitado) async {
    if (_perfilAtual == null) await carregarPerfilAtual();
    if (_perfilAtual == null) return false;

    // ✅ Multi-tenant: vendedor só acessa SUA loja
    return _perfilAtual!.storeId == storeIdRequisitado;
  }

  /// Valida ref de vendedor em link do catálogo (anti-fraude)
  Future<bool> validarRefVendedor(String vendedorUid, String storeId) async {
    // Verifica se o vendedor realmente pertence à loja do link
    return await vendedorPertenceALoja(vendedorUid, storeId);
  }

  // ==========================================================================
  // PERMISSÕES DINÂMICAS
  // ==========================================================================

  /// Carrega permissões atualizadas do Firestore
  Future<Map<String, bool>> carregarPermissoes(String vendedorUid, String storeId) async {
    try {
      final doc = await _db
          .collection('lojas')
          .doc(storeId)
          .collection('vendedores')
          .doc(vendedorUid)
          .get();

      if (!doc.exists) return Map.from(permissoesPadrao);

      final data = doc.data() ?? {};
      final permissoes = VendedorPerfil._parsePermissoes(data['permissoes']);

      // Mesclar com padrão (garantir campos obrigatórios)
      final resultado = Map<String, bool>.from(permissoesPadrao);
      resultado.addAll(permissoes);

      // ✅ Garantir que permissões bloqueadas NUNCA sejam true
      for (final bloqueada in permissoesBloqueadas) {
        resultado[bloqueada] = false;
      }

      return resultado;
    } catch (e) {
      debugPrint('⚠️ [VENDEDOR] Erro ao carregar permissões (type=${e.runtimeType})');
      return Map.from(permissoesPadrao);
    }
  }

  /// Verifica permissão específica (com cache)
  Future<bool> temPermissao(String permissaoKey) async {
    // Permissões bloqueadas: SEMPRE false
    if (permissoesBloqueadas.contains(permissaoKey)) {
      return false;
    }

    if (_perfilAtual == null) await carregarPerfilAtual();
    if (_perfilAtual == null) return false;

    // Recarregar permissões do Firestore (dinâmico)
    final permissoes = await carregarPermissoes(
      _perfilAtual!.uid,
      _perfilAtual!.storeId,
    );

    return permissoes[permissaoKey] == true;
  }

  /// Verifica se vendedor tem ALGUMA permissão liberada
  Future<bool> temAlgumaPermissao() async {
    if (_perfilAtual == null) await carregarPerfilAtual();
    if (_perfilAtual == null) return false;

    final permissoes = await carregarPermissoes(
      _perfilAtual!.uid,
      _perfilAtual!.storeId,
    );

    // Verifica se tem pelo menos uma permissão liberável ativa
    for (final p in permissoesLiberaveis) {
      if (permissoes[p] == true) return true;
    }

    return false;
  }

  // ==========================================================================
  // CRUD DE VENDEDORES (para admin)
  // ==========================================================================

  /// Cadastra novo vendedor (chamado pelo admin)
  Future<String?> cadastrarVendedor({
    required String email,
    required String senha,
    required String nome,
    required String telefone,
    required String storeId,
    required String adminUid,
    required String adminEmail,
    Map<String, bool>? permissoesIniciais,
    double? comissaoPercentual,
  }) async {
    try {
      // 1. Criar usuário no Firebase Auth
      // ⚠ R2-FIX: preferir UI com Auth secondary (vendedores_screen).
      // Este caminho na Auth principal troca currentUser — não usar na admin UI.
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: senha,
      );

      final uid = credential.user?.uid;
      if (uid == null) throw Exception('Falha ao criar usuário');

      final agora = DateTime.now();
      final permissoes = Map<String, bool>.from(permissoesPadrao);
      if (permissoesIniciais != null) {
        permissoes.addAll(permissoesIniciais);
      }

      // Garantir bloqueadas
      for (final b in permissoesBloqueadas) {
        permissoes[b] = false;
      }

      // 2. Criar documento em users/{uid}
      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'email': email.trim().toLowerCase(),
        'nome': nome,
        'telefone': telefone,
        'role': 'vendedor',
        'tipo': 'vendedor',
        'storeId': storeId,
        'store_id': storeId,
        'adminUid': adminUid,
        'adminEmail': adminEmail,
        'ativo': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 3. Criar documento em usuarios/{email} (sem senha)
      final emailKey = email.trim().toLowerCase();
      await _db.collection('usuarios').doc(emailKey).set({
        'authUid': uid,
        'email': emailKey,
        'nome': nome,
        'telefone': telefone,
        'tipo': 'vendedor',
        'role': 'vendedor',
        'store_id': storeId,
        'ownerStoreId': storeId,
        'ownerAdminEmail': adminEmail,
        'ativo': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _db.collection('usuarios').doc(emailKey).set(
        {'senha': FieldValue.delete()},
        SetOptions(merge: true),
      );

      // 4. Criar documento em lojas/{storeId}/vendedores/{uid}
      final vendedorPerfil = VendedorPerfil(
        uid: uid,
        email: email.trim().toLowerCase(),
        nome: nome,
        telefone: telefone,
        storeId: storeId,
        adminUid: adminUid,
        adminEmail: adminEmail,
        ativo: true,
        permissoes: permissoes,
        comissaoPercentual: comissaoPercentual,
        criadoEm: agora,
      );

      await _db
          .collection('lojas')
          .doc(storeId)
          .collection('vendedores')
          .doc(uid)
          .set(vendedorPerfil.toFirestore());

      // 5. Manter compatibilidade com lojas/{storeId}/members/{uid}
      await _db
          .collection('lojas')
          .doc(storeId)
          .collection('members')
          .doc(uid)
          .set({
        'role': 'seller',
        'email': email.trim().toLowerCase(),
        'name': nome,
        'joinedAt': FieldValue.serverTimestamp(),
        'createdBy': adminEmail,
      });

      debugPrint('✅ [VENDEDOR] Cadastrado: $email -> loja $storeId');
      return uid;
    } catch (e) {
      debugPrint('❌ [VENDEDOR] Erro ao cadastrar (type=${e.runtimeType})');
      return null;
    }
  }

  /// Lista vendedores de uma loja
  Future<List<VendedorPerfil>> listarVendedores(String storeId) async {
    try {
      final snapshot = await _db
          .collection('lojas')
          .doc(storeId)
          .collection('vendedores')
          .get();

      return snapshot.docs
          .map((doc) => VendedorPerfil.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('⚠️ [VENDEDOR] Erro ao listar (type=${e.runtimeType})');
      return [];
    }
  }

  /// Atualiza permissões de um vendedor (admin)
  Future<bool> atualizarPermissoes(
    String vendedorUid,
    String storeId,
    Map<String, bool> novasPermissoes,
  ) async {
    try {
      // Garantir bloqueadas
      final permissoes = Map<String, bool>.from(novasPermissoes);
      for (final b in permissoesBloqueadas) {
        permissoes[b] = false;
      }

      await _db
          .collection('lojas')
          .doc(storeId)
          .collection('vendedores')
          .doc(vendedorUid)
          .update({
        'permissoes': permissoes,
        'atualizadoEm': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ [VENDEDOR] Permissões atualizadas: $vendedorUid');
      return true;
    } catch (e) {
      debugPrint('❌ [VENDEDOR] Erro ao atualizar permissões (type=${e.runtimeType})');
      return false;
    }
  }

  /// Ativa/desativa vendedor
  Future<bool> alterarStatus(String vendedorUid, String storeId, bool ativo) async {
    try {
      await _db
          .collection('lojas')
          .doc(storeId)
          .collection('vendedores')
          .doc(vendedorUid)
          .update({
        'ativo': ativo,
        'atualizadoEm': FieldValue.serverTimestamp(),
      });

      await _db.collection('users').doc(vendedorUid).update({
        'ativo': ativo,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ [VENDEDOR] Status alterado: $vendedorUid -> ativo=$ativo');
      return true;
    } catch (e) {
      debugPrint('❌ [VENDEDOR] Erro ao alterar status (type=${e.runtimeType})');
      return false;
    }
  }

  // ==========================================================================
  // LINK DO CATÁLOGO COM TRACKING
  // ==========================================================================

  /// Gera link do catálogo com ref do vendedor
  String gerarLinkCatalogo() {
    if (_perfilAtual == null) return '';

    final storeId = _perfilAtual!.storeId;
    final vendedorUid = _perfilAtual!.uid;

    // Formato: /loja/{storeId}?ref={vendedorUid}
    return '/loja/$storeId?ref=$vendedorUid';
  }

  /// Gera URL completa do catálogo
  String gerarUrlCatalogoCompleta(String baseUrl) {
    final path = gerarLinkCatalogo();
    if (path.isEmpty) return '';

    // Remove barra final do baseUrl se houver
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$base$path';
  }

  // ==========================================================================
  // SESSÃO E HIVE
  // ==========================================================================

  /// Salva dados do vendedor na sessão Hive
  Future<void> salvarNaSessao() async {
    if (_perfilAtual == null) return;

    try {
      final sessao = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');

      await sessao.put('tipo_usuario', 'vendedor');
      await sessao.put('role', 'vendedor');
      await sessao.put('store_id', _perfilAtual!.storeId);
      await sessao.put('storeId', _perfilAtual!.storeId);
      await sessao.put('vendedor_uid', _perfilAtual!.uid);
      await sessao.put('vendedor_nome', _perfilAtual!.nome);
      await sessao.put('admin_uid', _perfilAtual!.adminUid);
      await sessao.put('is_root', false);

      debugPrint('✅ [VENDEDOR] Sessão salva: ${_perfilAtual!.email} -> loja ${_perfilAtual!.storeId}');
    } catch (e) {
      debugPrint('⚠️ [VENDEDOR] Erro ao salvar sessão (type=${e.runtimeType})');
    }
  }

  /// Carrega dados da sessão Hive
  Future<Map<String, dynamic>> carregarDaSessao() async {
    try {
      final sessao = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');

      return {
        'tipo_usuario': sessao.get('tipo_usuario'),
        'role': sessao.get('role'),
        'store_id': sessao.get('store_id'),
        'storeId': sessao.get('storeId'),
        'vendedor_uid': sessao.get('vendedor_uid'),
        'vendedor_nome': sessao.get('vendedor_nome'),
        'admin_uid': sessao.get('admin_uid'),
        'is_root': sessao.get('is_root'),
      };
    } catch (e) {
      debugPrint('⚠️ [VENDEDOR] Erro ao carregar sessão (type=${e.runtimeType})');
      return {};
    }
  }
}
