// lib/utils/role_utils.dart
// Utilitários centralizados para gerenciamento de roles/tipos de usuário
// Hierarquia: programador > admin > vendedor

import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Emails que SEMPRE são programadores (root) - NUNCA sobrescrever.
/// Alinhar com `functions/src/rootAccounts.js` (ROOT_ACCOUNT_EMAILS).
const Set<String> rootEmails = {
  'masterpalm26@gmail.com',
  'masterpalm@gmail.com', // fallback para migração
  'admin@masterpalm.com',
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

  /// Resolve o role correto para um usuário
  /// ROOT emails SEMPRE retornam programador
  static UserRole resolveRole({
    required String? email,
    String? firestoreRole,
    String? localRole,
  }) {
    // ROOT override - NUNCA sobrescrever
    if (isRootEmail(email)) {
      return UserRole.programador;
    }

    // Prioridade: Firestore > Local > Default (vendedor)
    if (firestoreRole != null && firestoreRole.isNotEmpty) {
      return firestoreRole.toUserRole();
    }

    if (localRole != null && localRole.isNotEmpty) {
      return localRole.toUserRole();
    }

    return UserRole.vendedor;
  }

  /// Carrega o role da sessão Hive
  static Future<UserRole> loadFromSession() async {
    try {
      final sessao = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');

      final email = (sessao.get('usuario_logado') ?? '').toString().trim().toLowerCase();
      final storedRole = (sessao.get('tipo_usuario') ?? '').toString();
      final isRoot = sessao.get('is_root') == true;

      // ROOT override
      if (isRoot || isRootEmail(email)) {
        return UserRole.programador;
      }

      return storedRole.toUserRole();
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

      final isRoot = isRootEmail(email);
      final finalRole = isRoot ? UserRole.programador : role;

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
    if (!isRootEmail(email)) return;

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
