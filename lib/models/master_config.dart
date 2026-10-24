// lib/models/master_config.dart

/// Configurações globais do aplicativo (apenas root).
///
/// A autoridade sobre este documento é o root canônico verificado (Firebase Auth + Firestore Rules);
/// nenhum segredo vive aqui. Campos legados (senha master, credenciais Mercado Pago) não são
/// lidos nem regravados: só os campos de [allowedFields] fazem round-trip.
class MasterConfig {
  /// Únicos campos que o cliente pode gravar em `app_config/master_config`.
  static const List<String> allowedFields = [
    'requirePlanForNewUsers',
    'usersWithUnlimitedAccess',
    'globalSettings',
    'lastUpdated',
    'updatedBy',
  ];

  bool requirePlanForNewUsers;

  List<String> usersWithUnlimitedAccess;

  Map<String, dynamic> globalSettings;

  DateTime? lastUpdated;

  String? updatedBy;

  MasterConfig({
    this.requirePlanForNewUsers = true,
    List<String>? usersWithUnlimitedAccess,
    Map<String, dynamic>? globalSettings,
    this.lastUpdated,
    this.updatedBy,
  })  : usersWithUnlimitedAccess = usersWithUnlimitedAccess ?? [],
        globalSettings = globalSettings ?? {};

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'requirePlanForNewUsers': requirePlanForNewUsers,
      'usersWithUnlimitedAccess': usersWithUnlimitedAccess,
      'globalSettings': globalSettings,
      'lastUpdated': lastUpdated?.toIso8601String(),
      'updatedBy': updatedBy,
    };
    assert(map.keys.every(allowedFields.contains));
    return map;
  }

  factory MasterConfig.fromMap(Map<String, dynamic> map) {
    final lastUpdatedRaw = map['lastUpdated'];
    return MasterConfig(
      requirePlanForNewUsers: map['requirePlanForNewUsers'] is bool
          ? map['requirePlanForNewUsers'] as bool
          : true,
      usersWithUnlimitedAccess: map['usersWithUnlimitedAccess'] is List
          ? List<String>.from(
              (map['usersWithUnlimitedAccess'] as List).whereType<String>())
          : [],
      globalSettings: map['globalSettings'] is Map
          ? Map<String, dynamic>.from(map['globalSettings'] as Map)
          : {},
      lastUpdated:
          lastUpdatedRaw is String ? DateTime.tryParse(lastUpdatedRaw) : null,
      updatedBy: map['updatedBy'] is String ? map['updatedBy'] as String : null,
    );
  }

  MasterConfig copyWith({
    bool? requirePlanForNewUsers,
    List<String>? usersWithUnlimitedAccess,
    Map<String, dynamic>? globalSettings,
    DateTime? lastUpdated,
    String? updatedBy,
  }) {
    return MasterConfig(
      requirePlanForNewUsers:
          requirePlanForNewUsers ?? this.requirePlanForNewUsers,
      usersWithUnlimitedAccess:
          usersWithUnlimitedAccess ?? this.usersWithUnlimitedAccess,
      globalSettings: globalSettings ?? this.globalSettings,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
