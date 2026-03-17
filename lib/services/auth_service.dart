// lib/services/auth_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'store_resolver_unified.dart';

/// Serviço de autenticação + sessão local (Hive)
class AuthService extends ChangeNotifier {
  final FirebaseAuth? _auth;
  final FirebaseFirestore? _db;
  final bool offline;

  // Construtor interno
  AuthService._({
    required FirebaseAuth? auth,
    required FirebaseFirestore? db,
    required this.offline,
  })  : _auth = auth,
        _db = db;

  /// ✅ Versão ONLINE (Firebase inicializado)
  factory AuthService() {
    return AuthService._(
      auth: FirebaseAuth.instance,
      db: FirebaseFirestore.instance,
      offline: false,
    );
  }

  /// ✅ Versão OFFLINE (quando não existe Firebase App)
  factory AuthService.offline() {
    debugPrint('[AUTH] Modo OFFLINE – AuthService.offline()');
    return AuthService._(
      auth: null,
      db: null,
      offline: true,
    );
  }

  User? get currentUser => offline ? null : _auth?.currentUser;

  // ==========================================================
  // Helpers (Hive)
  // ==========================================================
  Future<void> _ensureSessaoBox() async {
    if (!Hive.isBoxOpen('sessao')) {
      await Hive.openBox('sessao');
    }
  }

  /// Copia config da loja atual para o box global "config"
  Future<void> _ativarConfigDaLojaLocalmente(String storeId) async {
    if (storeId.isEmpty) return;

    const mainName = 'config';
    final perStoreName = 'config_$storeId';

    if (!Hive.isBoxOpen(mainName)) {
      await Hive.openBox(mainName);
    }
    if (!Hive.isBoxOpen(perStoreName)) {
      await Hive.openBox(perStoreName);
    }

    final mainCfg = Hive.box(mainName);
    final perCfg = Hive.box(perStoreName);

    // Limpa config ativa e carrega a da loja
    await mainCfg.clear();
    for (final key in perCfg.keys) {
      await mainCfg.put(key, perCfg.get(key));
    }

    // Garante store_id / store_slug na config ativa
    await mainCfg.put('store_id', storeId);
    await mainCfg.put('store_slug', storeId);
  }

  Future<void> _saveSession({
    required String email,
    required String tipo, // admin / vendedor / programador
    required String storeId, // ID da loja (admin: pode iniciar vazio)
  }) async {
    await _ensureSessaoBox();
    final box = Hive.box('sessao');

    await box.put('usuario_logado', email);
    await box.put('usuario_logado_email', email);
    await box.put('tipo_usuario', tipo);
    await box.put('store_id', storeId);

    // 🔹 Prepara config da loja atual (multi-loja no mesmo aparelho)
    if (storeId.isNotEmpty) {
      await _ativarConfigDaLojaLocalmente(storeId);
    }
  }

  // ==========================================================
  // CADASTRO: conta criada no login é SEMPRE admin (nunca vendedor nem programador).
  // Vendedor é criado dentro da loja pelo admin.
  // ==========================================================
  Future<String?> register({
    required String name,
    required String email,
    required String phone,
    required String pass,
  }) async {
    if (offline) {
      return 'Sem conexão com o servidor. Não é possível criar conta agora.';
    }

    final nome = name.trim();
    final mail = email.trim().toLowerCase();
    final telefone = phone.trim();
    final senha = pass.trim();

    if (nome.isEmpty || mail.isEmpty || telefone.isEmpty || senha.isEmpty) {
      return 'Preencha nome, e-mail, telefone e senha.';
    }

    try {
      final auth = _auth!;
      final db = _db!;

      // Cria credenciais no Auth
      final cred = await auth.createUserWithEmailAndPassword(
        email: mail,
        password: senha,
      );

      final user = cred.user;
      if (user != null) {
        await user.updateDisplayName(nome);
        // Força renovação do token para que Firestore tenha email no token (evita permission-denied)
        await user.getIdToken(true);
        // Verificação por e-mail (gratuita, Firebase)
        await user.sendEmailVerification();
        debugPrint('[AUTH] E-mail de verificação enviado para $mail');
      }

      // Grava dados do admin no Firestore
      await db.collection('usuarios').doc(mail).set({
        'nome': nome,
        'email': mail,
        'telefone': telefone,
        'tipo': 'admin', // CADASTRO INICIAL = ADMIN
        'permissoes': {
          'estoque': true,
          'clientes': true,
          'vendas': true,
          'precificacao': true,
          'fornecedores': true,
          'relatorios': true,
          'historico': true,
          'cadastro_usuarios': true,
          'licenca': true,
          'backup': true,
          'configuracoes': true,
          'alterar_pin': false,
        },
        'ownerStoreId': '', // admin não vincula loja aqui!
        'authUid': cred.user?.uid ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Salva sessão local
      await _saveSession(email: mail, tipo: 'admin', storeId: '');

      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'Este e-mail já está em uso.';
        case 'invalid-email':
          return 'E-mail inválido.';
        case 'weak-password':
          return 'Senha muito fraca.';
        case 'operation-not-allowed':
          return 'Cadastro desabilitado no momento.';
        default:
          return 'Falha ao criar conta: ${e.code}';
      }
    } catch (e) {
      return 'Erro inesperado: $e';
    }
  }

  // ==========================================================
  // LOGIN
  // ==========================================================
  Future<String?> signIn({
    required String email,
    required String pass,
  }) async {
    if (offline) {
      return 'Sem conexão com o servidor. Não é possível fazer login agora.';
    }

    final mail = email.trim().toLowerCase();
    final senha = pass.trim();

    if (mail.isEmpty || senha.isEmpty) {
      return 'Informe e-mail e senha.';
    }

    try {
      final auth = _auth!;
      final db = _db!;

      await auth.signInWithEmailAndPassword(email: mail, password: senha);

      // Obtém doc do usuário
      DocumentSnapshot<Map<String, dynamic>> snap =
          await db.collection('usuarios').doc(mail).get();

      // Caso o doc não exista (usuário legado salvo por UID)
      if (!snap.exists) {
        final uid = auth.currentUser?.uid ?? '';
        if (uid.isNotEmpty) {
          final q = await db
              .collection('usuarios')
              .where('authUid', isEqualTo: uid)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            final data = q.docs.first.data();
            await db.collection('usuarios').doc(mail).set(
                  {...data, 'email': mail},
                  SetOptions(merge: true),
                );
            snap = await db.collection('usuarios').doc(mail).get();
          } else {
            return 'Seu perfil está incompleto. Peça ao administrador.';
          }
        } else {
          return 'Seu perfil está incompleto. Peça ao administrador.';
        }
      }

      final data = snap.data() ?? {};
      final tipo = (data['tipo'] ?? '').toString().trim().toLowerCase();
      final ownerStoreId = (data['ownerStoreId'] ?? '').toString().trim();
      final storeId = (data['store_id'] ?? '').toString().trim();

      if (tipo.isEmpty) {
        return 'Seu tipo de usuário está vazio. Peça ao administrador.';
      }

      // ✅ VENDEDOR: precisa estar vinculado a uma loja de um admin
      if (tipo == 'vendedor') {
        if (ownerStoreId.isEmpty) {
          return 'Vendedor sem loja vinculada. Peça ao administrador.';
        }
        await _saveSession(email: mail, tipo: tipo, storeId: ownerStoreId);
      }

      // ✅ ADMIN / PROGRAMADOR: usa store_id próprio ou gera novo
      if (tipo == 'admin' || tipo == 'programador') {
        // Se não tiver store_id, será resolvido pelo StoreResolverService
        await _saveSession(email: mail, tipo: tipo, storeId: storeId);
      }

      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-credential':
        case 'wrong-password':
          return 'Credenciais inválidas.';
        case 'user-not-found':
          return 'Usuário não encontrado.';
        case 'invalid-email':
          return 'E-mail inválido.';
        case 'user-disabled':
          return 'Usuário desativado.';
        case 'network-request-failed':
          return 'Falha de rede. Verifique sua internet.';
        default:
          return 'Falha no login: ${e.code}';
      }
    } catch (e) {
      return 'Erro inesperado: $e';
    }
  }

  // ==========================================================
  // LOGOUT
  // ==========================================================
  Future<void> logout() async {
    debugPrint('🔐 [AUTH] Iniciando logout...');
    try {
      if (!offline) {
        await _auth?.signOut();
      }
    } finally {
      // ✅ CRÍTICO: Limpar TODOS os caches de loja para evitar mistura multi-tenant
      await StoreResolverUnified.clearAllCaches();

      // Limpar sessão local (redundância segura)
      if (Hive.isBoxOpen('sessao')) {
        final box = Hive.box('sessao');
        await box.put('usuario_logado', '');
        await box.put('usuario_logado_email', '');
        await box.put('tipo_usuario', '');
        await box.put('store_id', '');
      }

      debugPrint('✅ [AUTH] Logout completo - todos os caches limpos');
      notifyListeners();
    }
  }
}