// lib/models/user_profile.dart
// Modelo imutável de perfil unificado (users/usuarios). ETAPA 17. Não altera modelos existentes.

import '../core/user_profile_keys.dart';

/// Perfil do usuário autenticado resolvido de users ou usuarios.
/// [sourceCollection] indica de qual coleção veio ('users' ou 'usuarios').
class UserProfile {
  final String uid;
  final String email;
  final String role;
  final String? storeId;
  final bool isRoot;
  final String sourceCollection;
  final Map<String, dynamic> raw;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.role,
    this.storeId,
    required this.isRoot,
    required this.sourceCollection,
    Map<String, dynamic>? raw,
  }) : raw = raw ?? const {};

  /// Role não vazio (trim).
  bool get hasValidRole => role.trim().isNotEmpty;

  /// storeId presente e não vazio (trim).
  bool get hasValidStoreId =>
      storeId != null && storeId!.trim().isNotEmpty;

  /// Perfil considerado completo para decidir rota/permissão (ETAPA 17.1).
  bool get isComplete => hasValidRole && hasValidStoreId;

  /// Extrai role de um mapa (mesma ordem de fallback do app).
  static String _roleFromMap(Map<String, dynamic> d) {
    final v = d[kRole] ?? d[kTipo] ?? d[kTipoUsuario] ?? d[kUserType] ?? 'vendedor';
    return v.toString().trim().toLowerCase();
  }

  /// Extrai storeId de um mapa (mesma ordem de fallback do app).
  static String? _storeIdFromMap(Map<String, dynamic> d) {
    final v = d[kStoreId] ?? d[kStoreIdCamel] ?? d[kOwnerStoreId] ?? d[kLojaId] ?? d[kLojaIdCamel];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  factory UserProfile.fromMap({
    required String uid,
    required String email,
    required String sourceCollection,
    required Map<String, dynamic> data,
    bool isRoot = false,
  }) {
    final role = _roleFromMap(data);
    final storeId = _storeIdFromMap(data);
    return UserProfile(
      uid: uid,
      email: email,
      role: role.isEmpty ? 'vendedor' : role,
      storeId: storeId,
      isRoot: isRoot,
      sourceCollection: sourceCollection,
      raw: Map<String, dynamic>.from(data),
    );
  }
}
