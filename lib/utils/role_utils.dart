// lib/utils/role_utils.dart
// Utilitários centralizados para gerenciamento de roles/tipos de usuário
// Hierarquia: programador > admin > vendedor

import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Emails que SEMPRE são programadores (root) - NUNCA sobrescrever.
/// Alinhar com `functions/src/rootAccounts.js` (ROOT_ACCOUNT_EMAILS).
const Set<String> rootEmails = {
  'masterpalm26@gmail.com',
};

/// Tipos de usuário válidos
enum UserRole {
  programador,
  admin,
  vendedor,
}

/// Extensão para converter string em UserRole
extension UserRoleExtension on String {
  UserRole toUserRole() {
    final normalized = trim().toLowerCase();
    switch (normalized) {
      case 'programador':
      case 'root':
      case 'master':
        return UserRole.programador;
      case 'admin':
      case 'administrador':
      case 'owner':
        return UserRole.admin;
      default:
        return UserRole.vendedor;
    }
  }
}

/// Extensão para UserRole
extension UserRoleToString on UserRole {
  String get name {
    switch (this) {
      case UserRole.programador:
        return 'programador';
      case UserRole.admin:
        return 'admin';
      case UserRole.vendedor:
        return 'vendedor';
    }
  }

  /// Verifica se tem permissão de admin ou superior
  bool get isAdminOrHigher => this == UserRole.programador || this == UserRole.admin;

  /// Verifica se é root (programador)
  bool get isRoot => this == UserRole.programador;

  /// Pode ver valores financeiros globais?
  bool get canViewGlobalFinancials => isAdminOrHigher;

  /// Pode gerenciar planos?
  bool get canManagePlans => isAdminOrHigher;

  /// Precisa verificar plano próprio?
  bool get needsPlanCheck => this == UserRole.admin;
}

/// Classe utilitária para gerenciamento de roles
class RoleUtils {
  RoleUtils._();

  /// Verifica se o email é root (SEMPRE programador)
  static bool isRootEmail(String? email) {
    if (email == null || email.isEmpty) return false;
    return rootEmails.contains(email.trim().toLowerCase());
  }

  /// Root canônico: e-mail root com verificação concluída, a mesma exigência de `isRootAdmin()`
  /// nas Firestore Rules e de `functions/src/rootAccounts.js`.
  static bool isVerifiedRootAccount({
    required String? email,
    required bool emailVerified,
  }) {
    return emailVerified && isRootEmail(email);
  }

  /// Substitui o usuário do Firebase Auth nos testes.
  @visibleForTesting
  static User? Function()? currentUserOverride;

  static bool isVerifiedRootUser(User? user) {
    if (user == null) return false;
    return isVerifiedRootAccount(email: user.email, emailVerified: user.emailVerified);
  }

  /// Root de plataforma no cliente. Papéis no Firestore/Hive (`programador`, `is_root`), UIDs e
  /// listas remotas de e-mail não concedem root: só o usuário autenticado com e-mail root verificado.
  static bool isCurrentUserVerifiedRoot() {
    try {
      final override = currentUserOverride;
      return isVerifiedRootUser(override != null ? override() : FirebaseAuth.instance.currentUser);
    } catch (_) {
      return false;
    }
  }

  /// `programador` é exclusivo do root verificado; para qualquer outra conta vale como `admin`.
  static UserRole platformSafeRole(UserRole role, {required bool isVerifiedRoot}) {
    if (isVerifiedRoot) return UserRole.programador;
    return role == UserRole.programador ? UserRole.admin : role;
  }

  /// Mesmo contrato de [platformSafeRole] para o tipo guardado como texto na sessão.
  static String platformSafeTipo(String? tipo, {required bool isVerifiedRoot}) {
    if (isVerifiedRoot) return UserRole.programador.name;
    final raw = (tipo ?? '').trim();
    return raw.toUserRole() == UserRole.programador ? UserRole.admin.name : raw;
  }

  /// Único e-mail da administração Mestre de planos (P1).
  static const String masterPlanAdminEmail = 'masterpalm26@gmail.com';

  static bool isMasterPlanAdminEmail(String? email) {
    if (email == null || email.isEmpty) return false;
    return email.trim().toLowerCase() == masterPlanAdminEmail;
  }

  /// Resolve o role correto para um usuário.
  /// Root verificado é sempre programador; `programador` vindo do Firestore/Hive de outra conta vale admin.
  static UserRole resolveRole({
    required bool isVerifiedRoot,
    String? firestoreRole,
    String? localRole,
  }) {
    if (isVerifiedRoot) {
      return UserRole.programador;
    }

    // Prioridade: Firestore > Local > Default (vendedor)
    var role = UserRole.vendedor;
    if (firestoreRole != null && firestoreRole.isNotEmpty) {
      role = firestoreRole.toUserRole();
    } else if (localRole != null && localRole.isNotEmpty) {
      role = localRole.toUserRole();
    }
    return platformSafeRole(role, isVerifiedRoot: false);
  }

  /// Carrega o role da sessão Hive
  static Future<UserRole> loadFromSession() async {
    try {
      final sessao = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');

      final storedRole = (sessao.get('tipo_usuario') ?? '').toString();
      return platformSafeRole(
        storedRole.toUserRole(),
        isVerifiedRoot: isCurrentUserVerifiedRoot(),
      );
    } catch (e) {
      debugPrint('❌ [ROLE] Erro ao carregar role (type=${e.runtimeType})');
      return UserRole.vendedor;
    }
  }

  /// Salva o role na sessão Hive
  static Future<void> saveToSession({
    required String email,
    required UserRole role,
  }) async {
    try {
      final sessao = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');

      final isRoot = isRootEmail(email) && isCurrentUserVerifiedRoot();
      final finalRole = platformSafeRole(role, isVerifiedRoot: isRoot);

      await sessao.put('tipo_usuario', finalRole.name);
      await sessao.put('role', finalRole.name);
      await sessao.put('is_root', isRoot);

      debugPrint('✅ [ROLE] Salvo na sessão: ${finalRole.name} (isRoot: $isRoot)');
    } catch (e) {
      debugPrint('❌ [ROLE] Erro ao salvar role (type=${e.runtimeType})');
    }
  }

  /// Migra o role no Firestore se necessário
  /// Usado para corrigir users root que estão com role errado
  static Future<void> migrateIfNeeded({
    required String uid,
    required String email,
  }) async {
    if (!isRootEmail(email) || !isCurrentUserVerifiedRoot()) return;

    try {
      final db = FirebaseFirestore.instance;

      // Atualizar collection 'usuarios' (por email)
      await db.collection('usuarios').doc(email).set({
        'tipo': 'programador',
        'role': 'programador',
        'is_root': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Atualizar collection 'users' (por uid)
      await db.collection('users').doc(uid).set({
        'tipo': 'programador',
        'role': 'programador',
        'tipo_usuario': 'programador',
        'is_root': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('✅ [ROLE] Migrado $email para programador no Firestore');
    } catch (e) {
      debugPrint('⚠️ [ROLE] Erro ao migrar role no Firestore (type=${e.runtimeType})');
    }
  }

  /// Verifica permissão baseado no role
  static bool hasPermission(UserRole role, String permissionKey) {
    // Programador tem TODAS as permissões
    if (role == UserRole.programador) return true;

    // Admin tem a maioria das permissões
    if (role == UserRole.admin) {
      // Admin não pode alterar roles de programador
      if (permissionKey == 'manage_programmers') return false;
      return true;
    }

    // Vendedor tem permissões limitadas
    return false;
  }
}
